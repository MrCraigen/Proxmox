#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/asylumexp/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/asifma/lar-med-nadira

APP="Lar-med-Nadira"
var_tags="${var_tags:-education}"
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

# ─────────────────────────────────────────────────────────────────────────────
# ARM64 FIX: Pre-set TEMPLATE and TEMPLATE_STORAGE so build.func skips the
# online Proxmox template-metadata query (which 404s for custom ARM64 rootfs).
#
# The template name MUST match exactly what pveam list shows in your storage.
# Run this on your Proxmox host to verify:  pveam list network-iso
# ─────────────────────────────────────────────────────────────────────────────
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-network-iso}"
TEMPLATE="${TEMPLATE:-${TEMPLATE_STORAGE}:vztmpl/debian-bookworm-rootfs.tar.xz}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/lar-med-nadira ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop lar-med-nadira
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  cd /opt/lar-med-nadira
  git pull &>/dev/null
  npm install &>/dev/null
  npm run build &>/dev/null
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start lar-med-nadira
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
