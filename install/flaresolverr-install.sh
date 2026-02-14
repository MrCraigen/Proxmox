#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# Co-Author: remz1337
# Modified for ARM64: Uses Chromium instead of Chrome
# License: MIT | https://github.com/asylumexp/Proxmox/raw/main/LICENSE
# Source: https://github.com/FlareSolverr/FlareSolverr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y apt-transport-https
$STD apt-get install -y xvfb
$STD apt-get install -y wget
$STD apt-get install -y git
$STD apt-get install -y openssh-server
msg_ok "Installed Dependencies"

msg_info "Installing Chromium"
# Unhold chromium if it was held by previous scripts
apt-mark unhold chromium 2>/dev/null || true
$STD apt-get install -y chromium chromium-driver
msg_ok "Installed Chromium"

fetch_and_deploy_gh_release "flaresolverr" "FlareSolverr/FlareSolverr" "prebuild" "latest" "/opt/flaresolverr" "flaresolverr_linux_arm64.tar.gz"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/flaresolverr.service
[Unit]
Description=FlareSolverr
After=network.target
[Service]
SyslogIdentifier=flaresolverr
Restart=always
RestartSec=5
Type=simple
Environment="LOG_LEVEL=info"
Environment="CAPTCHA_SOLVER=none"
Environment="CHROME_EXE=/usr/bin/chromium"
WorkingDirectory=/opt/flaresolverr
ExecStart=python3 /opt/flaresolverr/src/flaresolverr.py
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now flaresolverr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
