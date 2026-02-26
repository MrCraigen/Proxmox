#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/GHJJ123/brainrotguard

APP="BrainRotGuard"
var_tags="${var_tags:-kids}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
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
  if [[ ! -d /opt/brainrotguard ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping Service"
  systemctl stop brainrotguard
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  cd /opt/brainrotguard
  git pull origin main &>/dev/null
  pip install -r requirements.txt --quiet &>/dev/null
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start brainrotguard
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} Don't forget to configure your .env file with:${CL}"
echo -e "${TAB}${BGN}BRG_BOT_TOKEN, BRG_ADMIN_CHAT_ID, BRG_PIN (optional)${CL}"
