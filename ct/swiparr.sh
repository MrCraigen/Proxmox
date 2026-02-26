#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/m3sserstudi0s/swiparr

APP="Swiparr"
var_tags="${var_tags:-arr;jellyfin}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
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
  if [[ ! -d /opt/swiparr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping Service"
  systemctl stop swiparr
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  cd /opt/swiparr
  git pull --quiet origin master
  npm install --silent
  npm run build --silent
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start swiparr
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4321${CL}"
