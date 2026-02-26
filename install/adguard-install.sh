#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/asylumexp/Proxmox/raw/main/LICENSE
# Source: https://adguard.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if command -v dpkg >/dev/null 2>&1; then
  arch="$(dpkg --print-architecture)"
else
  arch="$(uname -m)"
fi

case "$arch" in
  amd64|x86_64) adguard_pkg="AdGuardHome_linux_amd64.tar.gz" ;;
  arm64|aarch64) adguard_pkg="AdGuardHome_linux_arm64.tar.gz" ;;
  armv7l|armhf) adguard_pkg="AdGuardHome_linux_armv7.tar.gz" ;;
  *) msg_error "Unsupported architecture: $arch" && exit 1 ;;
esac

fetch_and_deploy_gh_release "AdGuardHome" "AdguardTeam/AdGuardHome" "prebuild" "latest" "/opt/AdGuardHome" "$adguard_pkg"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/AdGuardHome.service
[Unit]
Description=AdGuard Home: Network-level blocker
ConditionFileIsExecutable=/opt/AdGuardHome/AdGuardHome
After=syslog.target network-online.target

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/opt/AdGuardHome/AdGuardHome "-s" "run"
WorkingDirectory=/opt/AdGuardHome
StandardOutput=file:/var/log/AdGuardHome.out
StandardError=file:/var/log/AdGuardHome.err
Restart=always
RestartSec=10
EnvironmentFile=-/etc/sysconfig/AdGuardHome

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now AdGuardHome
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
