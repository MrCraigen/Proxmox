#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/amirkabiri/duckai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl git unzip
msg_ok "Installed Dependencies"

msg_info "Installing Bun (ARM64)"
curl -fsSL https://bun.sh/install | bash &>/dev/null
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
echo 'export BUN_INSTALL="$HOME/.bun"' >> /etc/profile.d/bun.sh
echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> /etc/profile.d/bun.sh
msg_ok "Installed Bun"

msg_info "Cloning DuckAI"
git clone --depth=1 https://github.com/amirkabiri/duckai /opt/duckai &>/dev/null
cd /opt/duckai
$BUN_INSTALL/bin/bun install --frozen-lockfile --production &>/dev/null
msg_ok "Cloned and built DuckAI"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/duckai.service
[Unit]
Description=DuckAI OpenAI-compatible API Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/duckai
ExecStart=/root/.bun/bin/bun run src/server.ts
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now duckai
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
