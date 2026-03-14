#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/afkarxyz/SpotiFLAC
#         https://github.com/jelte1/SpotiFLAC-Command-Line-Interface
#         https://windscribe.com

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  python3 \
  python3-pip \
  python3-venv \
  ffmpeg \
  jq \
  ca-certificates \
  apt-transport-https \
  gnupg
msg_ok "Installed Dependencies"

# ── Detect Architecture ──────────────────────────────────────────────────────
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

# ── Install SpotiFLAC CLI ─────────────────────────────────────────────────────
msg_info "Installing SpotiFLAC CLI"
RELEASE=$(curl -fsSL "https://api.github.com/repos/jelte1/SpotiFLAC-Command-Line-Interface/releases/latest" \
  | grep '"tag_name"' \
  | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$RELEASE" ]]; then
  msg_error "Failed to fetch SpotiFLAC release version from GitHub API"
  exit 1
fi

mkdir -p /opt/spotiflac

curl -fsSL \
  "https://github.com/jelte1/SpotiFLAC-Command-Line-Interface/releases/download/${RELEASE}/${SPOTIFLAC_BIN}" \
  -o "/opt/spotiflac/${SPOTIFLAC_BIN}"

chmod +x "/opt/spotiflac/${SPOTIFLAC_BIN}"
ln -sf "/opt/spotiflac/${SPOTIFLAC_BIN}" /usr/local/bin/spotiflac

echo "${RELEASE}" > /opt/spotiflac/version.txt
msg_ok "Installed SpotiFLAC CLI ${RELEASE} (${ARCH_LABEL})"

# ── Create Music Output Directory ─────────────────────────────────────────────
msg_info "Creating music output directory"
mkdir -p /mnt/music
chmod 755 /mnt/music
msg_ok "Created /mnt/music"

# ── Install Windscribe VPN CLI ────────────────────────────────────────────────
msg_info "Installing Windscribe VPN CLI (${ARCH_LABEL})"

# Install dependencies Windscribe needs
$STD apt-get install -y openvpn resolvconf net-tools iproute2 wireguard-tools

# Fetch latest stable release tag from GitHub API
WS_RELEASE=$(curl -fsSL "https://api.github.com/repos/Windscribe/Desktop-App/releases/latest" \
  | grep '"tag_name"' \
  | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$WS_RELEASE" ]]; then
  msg_error "Failed to fetch Windscribe release version from GitHub API"
  exit 1
fi

# Version number without leading 'v' for filename
WS_VER="${WS_RELEASE#v}"
WS_DEB="windscribe-cli_${WS_VER}_${WINDSCRIBE_ARCH}.deb"
WS_URL="https://github.com/Windscribe/Desktop-App/releases/download/${WS_RELEASE}/${WS_DEB}"

curl -fsSL "${WS_URL}" -o /tmp/windscribe_install.deb

if [[ ! -f /tmp/windscribe_install.deb ]] || [[ ! -s /tmp/windscribe_install.deb ]]; then
  msg_error "Failed to download Windscribe package from: ${WS_URL}"
  exit 1
fi

$STD dpkg -i /tmp/windscribe_install.deb || true
$STD apt-get install -f -y
rm -f /tmp/windscribe_install.deb
$STD systemctl enable windscribe 2>/dev/null || true
msg_ok "Installed Windscribe VPN CLI ${WS_RELEASE} (${ARCH_LABEL})"

# ── Windscribe Firewall Bypass (headless helper) ──────────────────────────────
# Allow Windscribe firewall rules to not block the container's internal traffic
if command -v windscribe &>/dev/null; then
  windscribe firewall off &>/dev/null || true
fi

# ── Create systemd Service for SpotiFLAC (optional looping daemon) ─────────────
msg_info "Creating SpotiFLAC systemd service"
cat <<'EOF' > /etc/systemd/system/spotiflac.service
[Unit]
Description=SpotiFLAC CLI Downloader Service
After=network-online.target windscribe.service
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
EOF

# ── Create default environment file ──────────────────────────────────────────
cat <<'EOF' > /opt/spotiflac/spotiflac.env
# SpotiFLAC environment configuration
# Edit this file to configure the service, then run:
#   systemctl daemon-reload && systemctl restart spotiflac

# The Spotify URL to sync (playlist, album, or track)
SPOTIFLAC_URL=

# Output directory for downloaded FLAC files
SPOTIFLAC_OUTPUT_DIR=/mnt/music

# Music service to use: tidal, qobuz, deezer, amazon
SPOTIFLAC_SERVICE=tidal

# How often to re-check for new tracks (minutes). 0 = run once
SPOTIFLAC_LOOP=60
EOF

$STD systemctl daemon-reload
# Do NOT enable/start the service automatically; user must configure the env file first
msg_ok "Created SpotiFLAC systemd service"

# ── Create helper usage script ────────────────────────────────────────────────
msg_info "Creating helper scripts"
cat <<'HELPEREOF' > /usr/local/bin/spotiflac-setup
#!/usr/bin/env bash
# SpotiFLAC quick-setup helper
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           SpotiFLAC + Windscribe Setup               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo " Binary   : $(readlink /usr/local/bin/spotiflac)"
echo " Version  : $(cat /opt/spotiflac/version.txt 2>/dev/null || echo 'unknown')"
echo " Arch     : $(uname -m)"
echo " Output   : /mnt/music"
echo ""
echo "━━━ Windscribe VPN ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 1. Login:      windscribe login"
echo " 2. Connect:    windscribe connect best"
echo " 3. Status:     windscribe status"
echo " 4. Disconnect: windscribe disconnect"
echo ""
echo "━━━ SpotiFLAC CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Manual download example:"
echo "   spotiflac 'https://open.spotify.com/album/...' /mnt/music \\"
echo "     --service tidal --use-album-subfolders --embed-lyrics"
echo ""
echo "━━━ Automated Service ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Edit:    nano /opt/spotiflac/spotiflac.env"
echo " Enable:  systemctl enable --now spotiflac"
echo " Logs:    journalctl -u spotiflac -f"
echo ""
HELPEREOF
chmod +x /usr/local/bin/spotiflac-setup
msg_ok "Created helper scripts"

# ── Motd ──────────────────────────────────────────────────────────────────────
motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned"
