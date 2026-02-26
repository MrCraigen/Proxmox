#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/m3sserstudi0s/swiparr

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
  git \
  sudo \
  make \
  g++ \
  gcc \
  unzip \
  gnupg \
  ca-certificates
msg_ok "Installed Dependencies"

msg_info "Installing Node.js"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

msg_info "Cloning Swiparr"
git clone --quiet https://github.com/m3sserstudi0s/swiparr.git /opt/swiparr
cd /opt/swiparr
msg_ok "Cloned Swiparr"

msg_info "Building Swiparr"
$STD npm install
NODE_OPTIONS="--max-old-space-size=1536" $STD npm run build
msg_ok "Built Swiparr"

msg_info "Running Database Migrations"
mkdir -p /opt/swiparr/data
DATABASE_URL=file:/opt/swiparr/data/swiparr.db $STD npm run db:migrate
msg_ok "Database Migrations Complete"

msg_info "Configuring Swiparr"
read -rp "Enter your Jellyfin URL (e.g. http://192.168.1.10:8096): " JELLYFIN_URL
while [[ -z "$JELLYFIN_URL" ]]; do
  msg_error "JELLYFIN_URL cannot be empty"
  read -rp "Enter your Jellyfin URL: " JELLYFIN_URL
done
AUTH_SECRET=$(openssl rand -hex 32)
msg_ok "Configuration complete"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/swiparr.service
[Unit]
Description=Swiparr - Tinder for your Jellyfin media library
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/swiparr
ExecStart=/usr/bin/node .next/standalone/server.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=swiparr
Environment=NODE_ENV=production
Environment=PORT=4321
Environment=DATABASE_URL=file:/opt/swiparr/data/swiparr.db
Environment=AUTH_SECRET=${AUTH_SECRET}
Environment=JELLYFIN_URL=${JELLYFIN_URL}

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --quiet --now swiparr
msg_ok "Created and Started Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned"
