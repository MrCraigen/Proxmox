#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Sources:
#   Gharmonize : https://github.com/G-grbz/Gharmonize
#   Windscribe  : https://windscribe.com/download?cpid=homepage

# ==============================================================================
# DNS REPAIR — must run BEFORE source/catch_errors/set -e
#
# The framework's catch_errors() enables set -Eeuo pipefail + ERR trap.
# Any failed command after that point kills the script immediately.
# We fix DNS here, while the shell is still lenient.
#
# NOTE: getent/ping can succeed via /etc/hosts even when external DNS is dead,
# so we probe with a real curl call.
# ==============================================================================
_write_dns() {
  cat > /etc/resolv.conf <<'RESOLV'
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0 trust-ad
RESOLV
}

_check_dns() {
  curl -fsSL --max-time 6 --head https://deb.debian.org/ -o /dev/null 2>/dev/null
}

_fix_dns() {
  if _check_dns; then
    return 0
  fi
  _write_dns
  sleep 1
  if ! _check_dns; then
    echo ""
    echo " ✖️  DNS is not working inside this container."
    echo "     Tried nameservers: 1.1.1.1 and 8.8.8.8"
    echo ""
    echo "     Fix on the Proxmox HOST before re-running:"
    echo "       pct set <CTID> --nameserver 1.1.1.1"
    echo "     Or set DNS in the CT's network/DNS options in the Proxmox UI."
    echo ""
    exit 1
  fi
}
_fix_dns

# ==============================================================================
# Framework bootstrap — strict error handling starts here
# ==============================================================================
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─── Dependencies ─────────────────────────────────────────────────────────────
# NOTE: resolvconf is intentionally excluded.
# Installing resolvconf overwrites /etc/resolv.conf as a post-install hook,
# which silently kills external DNS inside the LXC container.
# OpenVPN (required by Windscribe) does not need resolvconf in this setup.
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  git \
  gnupg \
  ca-certificates \
  lsb-release \
  openssl \
  iptables \
  openvpn \
  systemd
msg_ok "Installed Dependencies"

# ─── Re-pin DNS ───────────────────────────────────────────────────────────────
# apt post-install hooks (dbus, libc-bin triggers, etc.) can regenerate
# /etc/resolv.conf after the dependency install block above.
# Re-write our static nameservers now, before any external curl/git calls.
msg_info "Re-pinning DNS after apt"
_write_dns
msg_ok "DNS re-pinned (1.1.1.1 / 8.8.8.8)"

# ─── Detect Architecture ──────────────────────────────────────────────────────
ARCH=$(dpkg --print-architecture)   # amd64 | arm64
msg_info "Detected architecture: ${ARCH}"

# ─── Node.js 20.x ─────────────────────────────────────────────────────────────
# Download the NodeSource setup script to a temp file, then execute separately.
# Avoids the "syntax error / command not found" from $STD (silent()) wrapping
# a pipe-to-bash — the NodeSource script emits ANSI escape sequences that
# silent() tries to parse as shell commands when used with | bash -.
msg_info "Installing Node.js 20.x"
curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
$STD bash /tmp/nodesource_setup.sh
rm -f /tmp/nodesource_setup.sh
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

# ─── ffmpeg ───────────────────────────────────────────────────────────────────
msg_info "Installing ffmpeg"
$STD apt-get install -y ffmpeg
msg_ok "Installed ffmpeg"

# ─── yt-dlp ───────────────────────────────────────────────────────────────────
msg_info "Installing yt-dlp"
curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
  -o /usr/local/bin/yt-dlp
chmod a+rx /usr/local/bin/yt-dlp
msg_ok "Installed yt-dlp"

# ─── MKVToolNix ───────────────────────────────────────────────────────────────
msg_info "Installing MKVToolNix"
$STD apt-get install -y mkvtoolnix
msg_ok "Installed MKVToolNix"

# ─── Gharmonize ───────────────────────────────────────────────────────────────
msg_info "Installing Gharmonize"
mkdir -p /opt/gharmonize
$STD git clone https://github.com/G-grbz/Gharmonize /opt/gharmonize
mkdir -p /opt/gharmonize/{uploads,outputs,temp,cookies,local-inputs}
touch /opt/gharmonize/cookies/cookies.txt

# Capture dynamic values before heredoc (subshell expansion breaks inside EOF)
APP_SECRET=$(openssl rand -hex 32)
FFMPEG_PATH=$(which ffmpeg)

cat > /opt/gharmonize/.env <<EOF
ADMIN_PASSWORD=changeme
APP_SECRET=${APP_SECRET}
NODE_ENV=production
PORT=5174
YT_FORCE_IPV4=1
YT_APPLY_403_WORKAROUNDS=1
YTDLP_EXTRA=--force-ipv4
DATA_DIR=/opt/gharmonize
YTDLP_BIN=/usr/local/bin/yt-dlp
FFMPEG_BIN=${FFMPEG_PATH}
EOF

cd /opt/gharmonize
$STD npm install --omit=dev
msg_ok "Installed Gharmonize"

# ─── Systemd Service — Gharmonize ─────────────────────────────────────────────
msg_info "Creating Gharmonize Service"
NODE_BIN=$(which node)

cat > /etc/systemd/system/gharmonize.service <<EOF
[Unit]
Description=Gharmonize Media Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gharmonize
ExecStart=${NODE_BIN} /opt/gharmonize/app.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now gharmonize &>/dev/null
msg_ok "Created and Started Gharmonize Service"

# ─── Windscribe CLI ───────────────────────────────────────────────────────────
# Official Windscribe apt repo supports both amd64 and arm64 on Debian/Ubuntu.
msg_info "Installing Windscribe CLI (${ARCH})"

if [[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]]; then
  WS_ARCH="$ARCH"
else
  msg_error "Unsupported architecture for Windscribe: ${ARCH}"
  exit 1
fi

# Do NOT wrap with $STD — curl output is piped directly to gpg
curl -fsSL "https://repo.windscribe.com/debian/windscribe.gpg" \
  | gpg --dearmor -o /usr/share/keyrings/windscribe-archive-keyring.gpg

echo "deb [arch=${WS_ARCH} signed-by=/usr/share/keyrings/windscribe-archive-keyring.gpg] \
https://repo.windscribe.com/debian/ stable main" \
  > /etc/apt/sources.list.d/windscribe.list

$STD apt-get update
$STD apt-get install -y windscribe-cli
systemctl enable windscribe &>/dev/null || true
msg_ok "Installed Windscribe CLI"

# ─── Systemd Service — Windscribe firewall post-init ──────────────────────────
# Windscribe's default "auto" firewall kills ALL non-VPN traffic in LXC,
# breaking the container entirely. This one-shot service turns it off at boot
# after windscribed is up, so normal traffic works when no VPN is connected.
msg_info "Creating Windscribe post-init Service"
cat > /etc/systemd/system/windscribe-postinit.service <<'EOF'
[Unit]
Description=Windscribe firewall off (headless LXC safe mode)
After=windscribe.service
Requires=windscribe.service

[Service]
Type=oneshot
ExecStart=/usr/bin/windscribe firewall off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable windscribe-postinit &>/dev/null || true
msg_ok "Windscribe post-init Service created"

# ─── MOTD ─────────────────────────────────────────────────────────────────────
cat >> /etc/motd <<'MOTD'

 ╔══════════════════════════════════════════════════════════╗
 ║  Gharmonize  →  http://<CT-IP>:5174                      ║
 ║  Edit /opt/gharmonize/.env to set ADMIN_PASSWORD         ║
 ║  then: systemctl restart gharmonize                      ║
 ║                                                          ║
 ║  Windscribe VPN CLI:                                     ║
 ║    windscribe login <user> <password>                    ║
 ║    windscribe connect                                    ║
 ║    windscribe status                                     ║
 ║                                                          ║
 ║  Supported arches: amd64 · arm64                        ║
 ╚══════════════════════════════════════════════════════════╝

MOTD

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get clean
msg_ok "Cleaned"
