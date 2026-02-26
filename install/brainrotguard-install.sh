#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/GHJJ123/brainrotguard

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
apt-get install -y \
  curl \
  sudo \
  git \
  python3 \
  python3-pip \
  python3-venv \
  ffmpeg \
  &>/dev/null
msg_ok "Installed Dependencies"

msg_info "Installing BrainRotGuard"
mkdir -p /opt/brainrotguard
git clone --depth=1 https://github.com/GHJJ123/brainrotguard.git /opt/brainrotguard &>/dev/null
cd /opt/brainrotguard

# Create virtual environment and install Python deps
python3 -m venv /opt/brainrotguard/venv &>/dev/null
/opt/brainrotguard/venv/bin/pip install --quiet -r requirements.txt &>/dev/null

# Create default .env file with placeholder values
cat <<EOF >/opt/brainrotguard/.env
BRG_BOT_TOKEN=your_telegram_bot_token_here
BRG_ADMIN_CHAT_ID=your_chat_id_here
BRG_PIN=
EOF

# Copy example config if not already present
if [[ -f /opt/brainrotguard/config.example.yaml ]]; then
  cp /opt/brainrotguard/config.example.yaml /opt/brainrotguard/config.yaml
fi
msg_ok "Installed BrainRotGuard"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/brainrotguard.service
[Unit]
Description=BrainRotGuard - YouTube Approval System for Kids
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/brainrotguard
EnvironmentFile=/opt/brainrotguard/.env
ExecStart=/opt/brainrotguard/venv/bin/python main.py -c config.yaml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now brainrotguard &>/dev/null
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
apt-get autoremove -y &>/dev/null
apt-get autoclean -y &>/dev/null
msg_ok "Cleaned"
