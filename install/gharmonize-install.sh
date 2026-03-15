#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Sources:
#   Gharmonize : https://github.com/G-grbz/Gharmonize
#   Windscribe  : https://windscribe.com/download?cpid=homepage

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─── DNS Guard ────────────────────────────────────────────────────────────────
# LXC containers sometimes start without a working resolv.conf.
# Write a sane fallback before any curl/git/apt call touches the internet.
msg_info "Checking DNS"
if ! getent hosts debian.org &>/dev/null; then
  msg_info "DNS not resolving — writing fallback resolv.conf"
  cat > /etc/resolv.conf <<'RESOLV'
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0 trust-ad
RESOLV
  sleep 2
  if ! getent hosts debian.org &>/dev/null; then
    msg_error "DNS still not working after fallback. Check host bridge / DNS settings."
    exit 1
  fi
fi
msg_ok "DNS OK"

# ─── Dependencies ─────────────────────────────────────────────────────────────
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
  resolvconf \
  systemd
msg_ok "Installed Dependencies"

# ─── Detect Architecture ──────────────────────────────────────────────────────
ARCH=$(dpkg --print-architecture)   # amd64 | arm64
msg_info "Detected architecture: ${ARCH}"

# ─── Node.js 20.x ─────────────────────────────────────────────────────────────
# Download the NodeSource setup script first, then execute separately.
# This avoids the "syntax error" that occurs when $STD wraps a pipe-to-bash call
# and strips the subshell's ANSI/control output mid-stream.
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

curl -fsSL "https://repo.windscribe.com/debian/windscribe.gpg" \
  | gpg --dearmor -o /usr/share/keyrings/windscribe-archive-keyring.gpg

echo "deb [arch=${WS_ARCH} signed-by=/usr/share/keyrings/windscribe-archive-keyring.gpg] \
https://repo.windscribe.com/debian/ stable main" \
  > /etc/apt/sources.list.d/windscribe.list

$STD apt-get update
$STD apt-get install -y windscribe-cli
systemctl enable windscribe &>/dev/null || true
msg_ok "Installed Windscribe CLI"

# ─── Systemd Service — Windscribe post-init ───────────────────────────────────
# Windscribe's default "auto" firewall kills all non-VPN traffic in LXC.
# This one-shot disables it after windscribed comes up.
msg_info "Creating Windscribe post-init Service"
cat > /etc/systemd/system/windscribe-postinit.service <<'EOF'
[Unit]
Description=Windscribe post-init (disable firewall for headless LXC)
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
