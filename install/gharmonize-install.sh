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
  net-tools \
  iproute2 \
  systemd
msg_ok "Installed Dependencies"

# ─── Detect Architecture ──────────────────────────────────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH_LABEL="amd64"
  WINDSCRIBE_ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH_LABEL="arm64"
  WINDSCRIBE_ARCH="arm64"
else
  msg_error "Unsupported architecture: $ARCH (only x86_64 and aarch64 are supported)"
  exit 1
fi
msg_info "Detected architecture: ${ARCH} (${ARCH_LABEL})"

# ─── Wait for network / DNS ───────────────────────────────────────────────────
# Polls every 2s for up to 90s. Fixes systemd-resolved stub if present.
# This is the proven pattern from spotiflac-install.sh.
msg_info "Waiting for network connectivity"
WAIT_SECONDS=0
MAX_WAIT=90

if grep -q "127.0.0.53" /etc/resolv.conf 2>/dev/null; then
  rm -f /etc/resolv.conf
  printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
fi

until curl -fsSL --max-time 5 --head "https://github.com" &>/dev/null; do
  if (( WAIT_SECONDS >= MAX_WAIT )); then
    echo ""
    msg_info "Network diagnostics:"
    echo "  -- IP addresses --"
    ip -4 addr show 2>/dev/null || echo "  (ip command failed)"
    echo "  -- Default route --"
    ip route show default 2>/dev/null || echo "  (no default route)"
    echo "  -- /etc/resolv.conf --"
    cat /etc/resolv.conf 2>/dev/null || echo "  (missing)"
    echo "  -- DNS test via IP (bypass DNS) --"
    curl -fsSL --max-time 5 --head "https://1.1.1.1" &>/dev/null \
      && echo "  IP reachable — DNS is the problem" \
      || echo "  IP NOT reachable — no route to internet"
    GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
    if [[ -n "$GW" ]]; then
      ping -c 2 -W 2 "$GW" 2>/dev/null \
        && echo "  Gateway $GW reachable" \
        || echo "  Gateway $GW NOT reachable"
    fi
    msg_error "Network not available after ${MAX_WAIT}s — see diagnostics above"
    exit 1
  fi
  sleep 2
  WAIT_SECONDS=$(( WAIT_SECONDS + 2 ))
done
msg_ok "Network is available"

# ─── Node.js 20.x ─────────────────────────────────────────────────────────────
# Download setup script to a temp file first — avoids $STD (silent()) breaking
# when wrapping a pipe-to-bash (ANSI escape sequences cause "syntax error").
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
# Download the .deb directly from GitHub Releases — same approach as
# spotiflac-install.sh. Avoids the apt repo entirely (no GPG key import,
# no extra apt source, no DNS dependency on repo.windscribe.com at install time).
msg_info "Installing Windscribe VPN CLI (${ARCH_LABEL})"

WS_FALLBACK="v2.20.7"
WS_RELEASE=$(curl -fsSL --max-time 10 \
  "https://api.github.com/repos/Windscribe/Desktop-App/releases/latest" \
  2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)
[[ -z "$WS_RELEASE" ]] && WS_RELEASE="$WS_FALLBACK"

WS_VER="${WS_RELEASE#v}"
WS_DEB="windscribe-cli_${WS_VER}_${WINDSCRIBE_ARCH}.deb"
WS_URL="https://github.com/Windscribe/Desktop-App/releases/download/${WS_RELEASE}/${WS_DEB}"

curl -fsSL --max-time 120 "${WS_URL}" -o /tmp/windscribe_install.deb

if [[ ! -s /tmp/windscribe_install.deb ]]; then
  msg_error "Failed to download Windscribe package from: ${WS_URL}"
  exit 1
fi

$STD dpkg --force-depends -i /tmp/windscribe_install.deb || true
$STD apt-get install -f -y
rm -f /tmp/windscribe_install.deb

# ─── Windscribe service user ──────────────────────────────────────────────────
# windscribe-cli refuses to run as root. Create a dedicated system user.
useradd --system --shell /bin/bash --create-home windscribe 2>/dev/null || true

# Disable firewall as the windscribe user — prevents blocking all non-VPN traffic
su - windscribe -c "windscribe-cli firewall off" &>/dev/null || true

msg_ok "Installed Windscribe VPN CLI ${WS_RELEASE} (${ARCH_LABEL})"

# ─── ws helper ───────────────────────────────────────────────────────────────
# Wraps windscribe-cli to always run as the windscribe user.
# Usage: ws login <user> <pass> | ws connect best | ws status | ws disconnect
msg_info "Creating ws helper"
cat > /usr/local/bin/ws <<'WSEOF'
#!/usr/bin/env bash
# ws — run windscribe-cli as the windscribe user (refuses to run as root)
exec su - windscribe -c "windscribe-cli $*"
WSEOF
chmod +x /usr/local/bin/ws
msg_ok "Created ws helper (/usr/local/bin/ws)"

# ─── MOTD ─────────────────────────────────────────────────────────────────────
cat >> /etc/motd <<'MOTD'

 ╔══════════════════════════════════════════════════════════╗
 ║  Gharmonize  →  http://<CT-IP>:5174                      ║
 ║  Edit /opt/gharmonize/.env to set ADMIN_PASSWORD         ║
 ║  then: systemctl restart gharmonize                      ║
 ║                                                          ║
 ║  Windscribe VPN (run via ws helper, not as root):        ║
 ║    ws login <user> <password>                            ║
 ║    ws connect best                                       ║
 ║    ws status                                             ║
 ║    ws disconnect                                         ║
 ║                                                          ║
 ║  Supported arches: amd64 · arm64                        ║
 ╚══════════════════════════════════════════════════════════╝

MOTD

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned"
