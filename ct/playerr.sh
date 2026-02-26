#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/Maikboarder/Playerr

APP="Playerr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/playerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping ${APP} Service"
  systemctl stop playerr
  msg_ok "Stopped ${APP} Service"

  msg_info "Updating ${APP}"
  RELEASE=$(curl -fsSL "https://api.github.com/repos/Maikboarder/Playerr/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/')
  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    ASSET="Playerr-Linux-x64.tar.gz"
  else
    msg_error "Unsupported architecture: $ARCH"
    exit 1
  fi

  curl -fsSL "https://github.com/Maikboarder/Playerr/releases/download/${RELEASE}/${ASSET}" -o /tmp/playerr.tar.gz
  tar -xzf /tmp/playerr.tar.gz -C /opt/playerr --strip-components=1
  rm -f /tmp/playerr.tar.gz
  chmod +x /opt/playerr/Playerr
  msg_ok "Updated ${APP} to ${RELEASE}"

  msg_info "Starting ${APP} Service"
  systemctl start playerr
  msg_ok "Started ${APP} Service"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2727${CL}"
