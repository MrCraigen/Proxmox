#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/G-grbz/Gharmonize

APP="Gharmonize"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
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
  if [[ ! -d /opt/gharmonize ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping Service"
  systemctl stop gharmonize
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  cd /opt/gharmonize
  git pull &>/dev/null
  npm install --omit=dev &>/dev/null
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start gharmonize
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5174${CL}"
