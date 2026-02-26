#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/Maikboarder/Playerr

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
  ca-certificates \
  libicu-dev \
  libssl-dev \
  wget \
  gnupg \
  lsb-release
msg_ok "Installed Dependencies"

msg_info "Installing ${APP}"
RELEASE=$(curl -fsSL "https://api.github.com/repos/Maikboarder/Playerr/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/')
ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
  ASSET="Playerr-Linux-x64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
  # No arm64 Linux binary currently; inform and exit
  msg_error "No Linux ARM64 binary is currently provided by Playerr. Please check https://github.com/Maikboarder/Playerr/releases for updates."
  exit 1
else
  msg_error "Unsupported architecture: $ARCH"
  exit 1
fi

mkdir -p /opt/playerr
curl -fsSL "https://github.com/Maikboarder/Playerr/releases/download/${RELEASE}/${ASSET}" -o /tmp/playerr.tar.gz
tar -xzf /tmp/playerr.tar.gz -C /opt/playerr --strip-components=1
rm -f /tmp/playerr.tar.gz
chmod +x /opt/playerr/Playerr

# Create config directory
mkdir -p /opt/playerr/config
echo "${RELEASE}" >/opt/playerr/version.txt
msg_ok "Installed ${APP} ${RELEASE}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/playerr.service
[Unit]
Description=Playerr - Self-Hosted Game Library Manager
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/playerr
ExecStart=/opt/playerr/Playerr
Restart=on-failure
RestartSec=10
TimeoutStopSec=20
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now playerr
msg_ok "Created and Started Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
