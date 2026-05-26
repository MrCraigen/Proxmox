#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

APP="SparkyFitness"
var_tags="${var_tags:-fitness}"
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
  if [[ ! -d /opt/SparkyFitness ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Services"
  systemctl stop sparkyfitness-server
  systemctl stop nginx
  msg_ok "Stopped Services"

  msg_info "Updating ${APP}"
  cd /opt/SparkyFitness
  git fetch --tags --quiet
  LATEST=$(git describe --tags "$(git rev-list --tags --max-count=1)")
  CURRENT=$(cat /opt/SparkyFitness/.version 2>/dev/null || echo "unknown")
  if [[ "$CURRENT" == "$LATEST" ]]; then
    msg_ok "Already on latest version: ${LATEST}"
    systemctl start sparkyfitness-server
    systemctl start nginx
    exit
  fi
  git checkout "$LATEST" --quiet
  echo "$LATEST" >/opt/SparkyFitness/.version

  msg_info "Installing Server Dependencies"
  cd /opt/SparkyFitness/SparkyFitnessServer
  npm ci --omit=dev &>/dev/null
  msg_ok "Installed Server Dependencies"

  msg_info "Building Frontend"
  cd /opt/SparkyFitness/SparkyFitnessFrontend
  npm ci &>/dev/null
  npm run build &>/dev/null
  cp -r dist/* /var/www/sparkyfitness/
  msg_ok "Built Frontend"

  msg_info "Starting Services"
  systemctl start sparkyfitness-server
  systemctl start nginx
  msg_ok "Started Services"
  msg_ok "Updated to ${LATEST} successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
