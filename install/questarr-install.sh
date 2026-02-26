#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/Doezer/Questarr

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
  sudo \
  mc \
  git \
  build-essential
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 20"
$STD curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

msg_info "Installing Questarr"
RELEASE=$(curl -fsSL https://api.github.com/repos/Doezer/Questarr/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
mkdir -p /opt/questarr
$STD git clone --depth 1 --branch "${RELEASE}" https://github.com/Doezer/Questarr.git /opt/questarr
cd /opt/questarr
mkdir -p /opt/questarr/data
$STD npm install
$STD npm run build
msg_ok "Installed Questarr ${RELEASE}"

msg_info "Creating .env File"
cat <<EOF >/opt/questarr/.env
PORT=5000
HOST=0.0.0.0
NODE_ENV=production
SQLITE_DB_PATH=/opt/questarr/data/sqlite.db
EOF
msg_ok "Created .env File"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/questarr.service
[Unit]
Description=Questarr - Video Games Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/questarr
EnvironmentFile=/opt/questarr/.env
ExecStart=/usr/bin/node /opt/questarr/dist/index.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now questarr &>/dev/null
msg_ok "Created and Started Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
