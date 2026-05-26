#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tom Frenzel (tomfrenzel) | ARM64 port: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

APP="SparkyFitness"
var_tags="${var_tags:-health;fitness}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
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

  if [[ ! -d /opt/sparkyfitness ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(cat /opt/sparkyfitness/.version 2>/dev/null || echo "none")
  LATEST=$(git ls-remote --tags --sort="v:refname" \
    https://github.com/CodeWithCJ/SparkyFitness.git \
    | grep -v '\^{}' | tail -1 | sed 's|.*refs/tags/||')

  if [[ "$CURRENT" == "$LATEST" ]]; then
    msg_ok "Already on latest version: ${LATEST}"
    exit
  fi

  msg_info "Stopping Services"
  systemctl stop sparkyfitness-server nginx
  msg_ok "Stopped Services"

  msg_info "Backing up data"
  mkdir -p /opt/sparkyfitness_backup
  [[ -d /opt/sparkyfitness/SparkyFitnessServer/uploads ]] && \
    cp -r /opt/sparkyfitness/SparkyFitnessServer/uploads /opt/sparkyfitness_backup/
  [[ -d /opt/sparkyfitness/SparkyFitnessServer/backup ]] && \
    cp -r /opt/sparkyfitness/SparkyFitnessServer/backup /opt/sparkyfitness_backup/
  msg_ok "Backed up data"

  msg_info "Pulling ${LATEST}"
  rm -rf /opt/sparkyfitness
  git clone --branch "$LATEST" --depth 1 \
    https://github.com/CodeWithCJ/SparkyFitness.git /opt/sparkyfitness &>/dev/null
  echo "$LATEST" > /opt/sparkyfitness/.version
  # Re-link env
  ln -sf /etc/sparkyfitness/.env /opt/sparkyfitness/SparkyFitnessServer/.env
  msg_ok "Pulled ${LATEST}"

  msg_info "Updating Backend"
  cd /opt/sparkyfitness/SparkyFitnessServer
  HUSKY=0 $STD pnpm install --ignore-scripts
  msg_ok "Updated Backend"

  msg_info "Updating Frontend (Patience)"
  cd /opt/sparkyfitness
  HUSKY=0 $STD pnpm install --ignore-scripts
  cd /opt/sparkyfitness/SparkyFitnessFrontend
  $STD pnpm run build
  cp -a /opt/sparkyfitness/SparkyFitnessFrontend/dist/. /var/www/sparkyfitness/
  msg_ok "Updated Frontend"

  msg_info "Restoring data"
  cp -r /opt/sparkyfitness_backup/. /opt/sparkyfitness/SparkyFitnessServer/
  rm -rf /opt/sparkyfitness_backup
  msg_ok "Restored data"

  msg_info "Starting Services"
  systemctl start sparkyfitness-server nginx
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
