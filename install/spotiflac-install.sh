#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/afkarxyz/SpotiFLAC
#         https://github.com/jelte1/SpotiFLAC-Command-Line-Interface
#         https://github.com/Windscribe/Desktop-App

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl wget python3 python3-pip python3-venv ffmpeg jq \
  ca-certificates apt-transport-https gnupg \
  openvpn resolvconf net-tools iproute2 wireguard-tools
msg_ok "Installed Dependencies"

# Detect Architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH_LABEL="amd64"
  SPOTIFLAC_BIN="SpotiFLAC-Linux-x86_64"
  WINDSCRIBE_ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH_LABEL="arm64"
  SPOTIFLAC_BIN="SpotiFLAC-Linux-arm64"
  WINDSCRIBE_ARCH="arm64"
else
  msg_error "Unsupported architecture: $ARCH (only x86_64 and aarch64 are supported)"
  exit 1
fi
msg_info "Detected architecture: ${ARCH} (${ARCH_LABEL})"

# Install SpotiFLAC CLI
msg_info "Installing SpotiFLAC CLI"

# Pinned fallback version — update_script() fetches dynamically on future upgrades
SPOTIFLAC_FALLBACK="v1.0.23"

SPOTIFLAC_RELEASE=""
SF_API_RESP=$(curl -fsSL --max-time 10 \
  "https://api.github.com/repos/jelte1/SpotiFLAC-Command-Line-Interface/releases/latest" \
  2>/dev/null || true)
if [[ -n "$SF_API_RESP" ]]; then
  SPOTIFLAC_RELEASE=$(echo "$SF_API_RESP" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi
[[ -z "$SPOTIFLAC_RELEASE" ]] && SPOTIFLAC_RELEASE="$SPOTIFLAC_FALLBACK"
msg_info "Using SpotiFLAC version: ${SPOTIFLAC_RELEASE}"

mkdir -p /opt/spotiflac

curl -fsSL --max-time 120 \
  "https://github.com/jelte1/SpotiFLAC-Command-Line-Interface/releases/download/${SPOTIFLAC_RELEASE}/${SPOTIFLAC_BIN}" \
  -o "/opt/spotiflac/${SPOTIFLAC_BIN}"

if [[ ! -s "/opt/spotiflac/${SPOTIFLAC_BIN}" ]]; then
  msg_error "Failed to download SpotiFLAC binary"
  exit 1
fi

chmod +x "/opt/spotiflac/${SPOTIFLAC_BIN}"
ln -sf "/opt/spotiflac/${SPOTIFLAC_BIN}" /usr/local/bin/spotiflac
echo "${SPOTIFLAC_RELEASE}" > /opt/spotiflac/version.txt
msg_ok "Installed SpotiFLAC CLI ${SPOTIFLAC_RELEASE} (${ARCH_LABEL})"

# Create Music Output Directory
msg_info "Creating music output directory"
mkdir -p /mnt/music
chmod 755 /mnt/music
msg_ok "Created /mnt/music"

# Install Windscribe VPN CLI
msg_info "Installing Windscribe VPN CLI (${ARCH_LABEL})"

# Pinned fallback version — update_script() fetches dynamically on future upgrades
WS_FALLBACK="v2.20.7"

WS_RELEASE=""
WS_API_RESP=$(curl -fsSL --max-time 10 \
  "https://api.github.com/repos/Windscribe/Desktop-App/releases/latest" \
  2>/dev/null || true)
if [[ -n "$WS_API_RESP" ]]; then
  WS_RELEASE=$(echo "$WS_API_RESP" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi
[[ -z "$WS_RELEASE" ]] && WS_RELEASE="$WS_FALLBACK"
msg_info "Using Windscribe version: ${WS_RELEASE}"

WS_VER="${WS_RELEASE#v}"
WS_DEB="windscribe-cli_${WS_VER}_${WINDSCRIBE_ARCH}.deb"
WS_URL="https://github.com/Windscribe/Desktop-App/releases/download/${WS_RELEASE}/${WS_DEB}"

curl -fsSL --max-time 120 "${WS_URL}" -o /tmp/windscribe_install.deb

if [[ ! -s /tmp/windscribe_install.deb ]]; then
  msg_error "Failed to download Windscribe package from: ${WS_URL}"
  exit 1
fi

$STD dpkg -i /tmp/windscribe_install.deb || true
$STD apt-get install -f -y
rm -f /tmp/windscribe_install.deb
$STD systemctl enable windscribe 2>/dev/null || true
msg_ok "Installed Windscribe VPN CLI ${WS_RELEASE} (${ARCH_LABEL})"

# Disable kill-switch by default so container traffic works before VPN login
if command -v windscribe-cli &>/dev/null; then
  windscribe-cli firewall off &>/dev/null || true
fi

# Create systemd Service for SpotiFLAC
msg_info "Creating SpotiFLAC systemd service"
cat > /etc/systemd/system/spotiflac.service << 'SVCEOF'
[Unit]
Description=SpotiFLAC CLI Downloader Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=-/opt/spotiflac/spotiflac.env
ExecStart=/usr/local/bin/spotiflac \
  ${SPOTIFLAC_URL} \
  ${SPOTIFLAC_OUTPUT_DIR:-/mnt/music} \
  --service ${SPOTIFLAC_SERVICE:-tidal} \
  --use-artist-subfolders \
  --use-album-subfolders \
  --embed-lyrics \
  --loop ${SPOTIFLAC_LOOP:-60}
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SVCEOF

# Create default environment file
cat > /opt/spotiflac/spotiflac.env << 'ENVEOF'
# SpotiFLAC environment configuration
# Edit this file, then run:
#   systemctl daemon-reload && systemctl restart spotiflac

# Spotify URL to sync (playlist, album, or track)
SPOTIFLAC_URL=

# Output directory for downloaded FLAC files
SPOTIFLAC_OUTPUT_DIR=/mnt/music

# Music service: tidal, qobuz, deezer, amazon
SPOTIFLAC_SERVICE=tidal

# Re-check interval in minutes (0 = run once and exit)
SPOTIFLAC_LOOP=60
ENVEOF

$STD systemctl daemon-reload
msg_ok "Created SpotiFLAC systemd service"

# Create helper usage script
msg_info "Creating helper scripts"
cat > /usr/local/bin/spotiflac-setup << 'HELPEREOF'
#!/usr/bin/env bash
echo ""
echo "=== SpotiFLAC + Windscribe Setup ========================"
echo ""
echo " Binary   : $(readlink /usr/local/bin/spotiflac)"
echo " Version  : $(cat /opt/spotiflac/version.txt 2>/dev/null || echo 'unknown')"
echo " Arch     : $(uname -m)"
echo " Output   : /mnt/music"
echo ""
echo "=== Windscribe VPN ======================================"
echo " 1. Login:      windscribe-cli login <user> <pass>"
echo " 2. Connect:    windscribe-cli connect best"
echo " 3. Status:     windscribe-cli status"
echo " 4. Disconnect: windscribe-cli disconnect"
echo ""
echo "=== SpotiFLAC Manual Download =========================="
echo " spotiflac 'https://open.spotify.com/album/...' /mnt/music \\"
echo "   --service tidal --use-album-subfolders --embed-lyrics"
echo ""
echo "=== Automated Service =================================="
echo " Edit:    nano /opt/spotiflac/spotiflac.env"
echo " Enable:  systemctl enable --now spotiflac"
echo " Logs:    journalctl -u spotiflac -f"
echo ""
HELPEREOF
chmod +x /usr/local/bin/spotiflac-setup
msg_ok "Created helper scripts"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned"
