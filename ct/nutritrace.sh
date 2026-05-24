#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 MrCraigen
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/TraceApps/nutritrace

APP="NutriTrace"
var_tags="${var_tags:-nutrition}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/nutritrace ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop nutritrace
  msg_ok "Stopped Service"

  msg_info "Pulling Latest Changes"
  cd /opt/nutritrace
  git pull origin main &>/dev/null
  msg_ok "Pulled Latest Changes"

  msg_info "Building Frontend"
  npm install &>/dev/null
  npm run build &>/dev/null
  msg_ok "Built Frontend"

  msg_info "Installing Server Dependencies"
  cd /opt/nutritrace/server
  npm install --omit=dev &>/dev/null
  msg_ok "Installed Server Dependencies"

  msg_info "Starting Service"
  systemctl start nutritrace
  msg_ok "Started Service"
  msg_ok "Updated Successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3001${CL}"
