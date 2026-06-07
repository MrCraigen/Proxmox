#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://ollama.com/

APP="Ollama"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-40}"
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
  if [[ ! -f /usr/local/bin/ollama ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping Service"
  systemctl stop ollama
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  LATEST=$(curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  curl -fsSL "https://github.com/ollama/ollama/releases/download/${LATEST}/ollama-linux-arm64.tar.gz" \
    | tar -xz -C /usr/local
  msg_ok "Updated ${APP} to ${LATEST}"

  msg_info "Starting Service"
  systemctl start ollama
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:11434${CL}"
echo -e "${INFO}${YW} To pull a model inside the LXC:${CL}"
echo -e "${TAB}${BGN}ollama pull gemma3:12b${CL}"
