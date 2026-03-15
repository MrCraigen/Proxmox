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
  systemd
msg_ok "Installed Dependencies"

# ─── Detect Architecture ──────────────────────────────────────────────────────
ARCH=$(dpkg --print-architecture)   # amd64 | arm64
msg_info "Detected architecture: ${ARCH}"

# ─── Node.js 20.x ─────────────────────────────────────────────────────────────
msg_info "Installing Node.js 20.x"
$STD curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

# ─── ffmpeg ───────────────────────────────────────────────────────────────────
msg_info "Installing ffmpeg"
$STD apt-get install -y ffmpeg
msg_ok "Installed ffmpeg"

# ─── yt-dlp ───────────────────────────────────────────────────────────────────
msg_info "Installing yt-dlp"
$STD curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
chmod a+rx /usr/local/bin/yt-dlp
msg_ok "Installed yt-dlp"

# ─── MKVToolNix ───────────────────────────────────────────────────────────────
msg_info "Installing MKVToolNix"
$STD apt-get install -y mkvtoolnix
msg_ok "Installed MKVToolNix"

# ─── Gharmonize ───────────────────────────────────────────────────────────────
msg_info "Installing Gharmonize"
mkdir -p /opt/gharmonize
cd /opt/gharmonize
$STD git clone https://github.com/G-grbz/Gharmonize .

# Create required directories
mkdir -p /opt/gharmonize/{uploads,outputs,temp,cookies,local-inputs}
touch /opt/gharmonize/cookies/cookies.txt

# Generate a secure APP_SECRET and a default .env
APP_SECRET=$(openssl rand -hex 32)
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
FFMPEG_BIN=$(which ffmpeg)
EOF

# Install npm dependencies (no Electron build — server mode only)
$STD npm install --omit=dev
msg_ok "Installed Gharmonize"

# ─── Systemd Service for Gharmonize ───────────────────────────────────────────
msg_info "Creating Gharmonize Service"
cat > /etc/systemd/system/gharmonize.service <<EOF
[Unit]
Description=Gharmonize Media Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gharmonize
ExecStart=/usr/bin/node /opt/gharmonize/app.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now gharmonize &>/dev/null
msg_ok "Created and Started Gharmonize Service"

# ─── Windscribe CLI ───────────────────────────────────────────────────────────
# Windscribe officially supports both AMD64 (amd64) and ARM64 (aarch64) on
# Debian/Ubuntu. The CLI .deb packages are fetched directly from Windscribe's
# repo for the correct architecture.
# NOTE: ARM64 support was added in Windscribe CLI v2.x.
#       Older versions were x86-only. Always fetch from the official repo.

msg_info "Installing Windscribe CLI (${ARCH})"

# Map Debian arch to Windscribe arch string
if [[ "$ARCH" == "amd64" ]]; then
  WS_ARCH="amd64"
elif [[ "$ARCH" == "arm64" ]]; then
  WS_ARCH="arm64"
else
  msg_error "Unsupported architecture for Windscribe: ${ARCH}"
  exit 1
fi

# Add Windscribe apt repository (supports both amd64 and arm64)
curl -fsSL https://repo.windscribe.com/debian/windscribe.gpg \
  | gpg --dearmor -o /usr/share/keyrings/windscribe-archive-keyring.gpg

echo "deb [arch=${WS_ARCH} signed-by=/usr/share/keyrings/windscribe-archive-keyring.gpg] \
https://repo.windscribe.com/debian/ stable main" \
  | tee /etc/apt/sources.list.d/windscribe.list > /dev/null

$STD apt-get update
$STD apt-get install -y windscribe-cli

# Enable the Windscribe daemon at boot
systemctl enable windscribe &>/dev/null || true
msg_ok "Installed Windscribe CLI"

# ─── Post-install note ────────────────────────────────────────────────────────
msg_info "Setting Windscribe firewall mode (off by default)"
# Run in background after boot — windscribed must be up first
cat > /etc/systemd/system/windscribe-postinit.service <<EOF
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
msg_ok "Windscribe post-init service created"

# ─── Motd hint ────────────────────────────────────────────────────────────────
cat >> /etc/motd <<'MOTD'

 ╔══════════════════════════════════════════════════════════╗
 ║  Gharmonize is running on port 5174                      ║
 ║  Edit /opt/gharmonize/.env to set your ADMIN_PASSWORD    ║
 ║                                                          ║
 ║  Windscribe VPN CLI (use to route yt-dlp traffic):       ║
 ║    windscribe login <user> <password>                    ║
 ║    windscribe connect                                    ║
 ║    windscribe status                                     ║
 ║                                                          ║
 ║  Architectures supported: amd64 and arm64               ║
 ╚══════════════════════════════════════════════════════════╝

MOTD

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get clean
msg_ok "Cleaned"
