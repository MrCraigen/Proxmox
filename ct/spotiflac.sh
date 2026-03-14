#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/MrCraigen/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/afkarxyz/SpotiFLAC
#         https://github.com/jelte1/SpotiFLAC-Command-Line-Interface
#         https://windscribe.com

APP="SpotiFLAC"
var_tags="${var_tags:-music;downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-yes}"           # Required for Windscribe VPN
var_ns="${var_ns:-1.1.1.1}"         # Force real DNS -- avoids broken systemd-resolved stub

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -L /usr/local/bin/spotiflac ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    SPOTIFLAC_BIN="SpotiFLAC-Linux-x86_64"
    WINDSCRIBE_ARCH="amd64"
  elif [[ "$ARCH" == "aarch64" ]]; then
    SPOTIFLAC_BIN="SpotiFLAC-Linux-arm64"
    WINDSCRIBE_ARCH="arm64"
  else
    msg_error "Unsupported architecture: $ARCH"
    exit 1
  fi

  msg_info "Stopping ${APP} Service"
  systemctl stop spotiflac 2>/dev/null || true
  msg_ok "Stopped ${APP} Service"

  msg_info "Updating SpotiFLAC CLI"
  RELEASE=""
  SF_API=$(curl -fsSL --max-time 10 \
    "https://api.github.com/repos/jelte1/SpotiFLAC-Command-Line-Interface/releases/latest" \
    2>/dev/null || true)
  [[ -n "$SF_API" ]] && RELEASE=$(echo "$SF_API" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)
  [[ -z "$RELEASE" ]] && RELEASE=$(cat /opt/spotiflac/version.txt 2>/dev/null || echo "v1.0.23")
  curl -fsSL --max-time 120 \
    "https://github.com/jelte1/SpotiFLAC-Command-Line-Interface/releases/download/${RELEASE}/${SPOTIFLAC_BIN}" \
    -o "/opt/spotiflac/${SPOTIFLAC_BIN}"
  chmod +x "/opt/spotiflac/${SPOTIFLAC_BIN}"
  ln -sf "/opt/spotiflac/${SPOTIFLAC_BIN}" /usr/local/bin/spotiflac
  echo "${RELEASE}" > /opt/spotiflac/version.txt
  msg_ok "Updated SpotiFLAC CLI to ${RELEASE}"

  msg_info "Updating Windscribe VPN CLI"
  WS_RELEASE=""
  WS_API=$(curl -fsSL --max-time 10 \
    "https://api.github.com/repos/Windscribe/Desktop-App/releases/latest" \
    2>/dev/null || true)
  [[ -n "$WS_API" ]] && WS_RELEASE=$(echo "$WS_API" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)
  [[ -z "$WS_RELEASE" ]] && WS_RELEASE="v2.20.7"
  WS_VER="${WS_RELEASE#v}"
  WS_DEB="windscribe-cli_${WS_VER}_${WINDSCRIBE_ARCH}.deb"
  WS_URL="https://github.com/Windscribe/Desktop-App/releases/download/${WS_RELEASE}/${WS_DEB}"
  curl -fsSL --max-time 120 "${WS_URL}" -o /tmp/windscribe_install.deb
  dpkg -i /tmp/windscribe_install.deb &>/dev/null || true
  apt-get install -f -y &>/dev/null
  rm -f /tmp/windscribe_install.deb
  msg_ok "Updated Windscribe VPN CLI to ${WS_RELEASE}"

  msg_info "Starting ${APP} Service"
  systemctl start spotiflac 2>/dev/null || true
  msg_ok "Started ${APP} Service"

  msg_ok "Updated ${APP} successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Run the setup guide inside the container:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}spotiflac-setup${CL}"
echo -e "${INFO}${YW} Music output directory:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/mnt/music${CL}"
echo -e "${INFO}${YW} Configure VPN first with:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}windscribe login${CL}"
