#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021
# License: MIT | https://github.com/asylumexp/Proxmox/raw/main/LICENSE
# Source: https://github.com/element-hq/synapse
# Modified for ARM64 compatibility: uses pip/venv instead of matrix.org apt repo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  build-essential \
  libffi-dev \
  libssl-dev \
  libjpeg-dev \
  libxslt1-dev \
  libpq-dev \
  rustc \
  cargo \
  pkg-config
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

read -p "${TAB3}Please enter the name for your server: " servername

msg_info "Installing Element Synapse"

# Create venv and install Synapse via pip (ARM64 compatible)
mkdir -p /opt/venv
python3 -m venv /opt/venv/synapse
$STD /opt/venv/synapse/bin/pip install --upgrade pip
$STD /opt/venv/synapse/bin/pip install "matrix-synapse[all]"

# Generate config
mkdir -p /etc/matrix-synapse
/opt/venv/synapse/bin/python -m synapse.app.homeserver \
  --generate-config \
  --server-name "$servername" \
  --report-stats=no \
  --config-path /etc/matrix-synapse/homeserver.yaml

# Bind to all interfaces instead of localhost only
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/matrix-synapse/homeserver.yaml
sed -i "s/'::1', //g" /etc/matrix-synapse/homeserver.yaml

# Add registration and shared secret settings
SECRET=$(openssl rand -hex 32)
ADMIN_PASS="$(openssl rand -base64 18 | cut -c1-13)"
echo "enable_registration_without_verification: true" >>/etc/matrix-synapse/homeserver.yaml
echo "registration_shared_secret: ${SECRET}" >>/etc/matrix-synapse/homeserver.yaml

# Create a dedicated system user for synapse
adduser --system --group --no-create-home --home /var/lib/matrix-synapse synapse 2>/dev/null || true
mkdir -p /var/lib/matrix-synapse /var/log/matrix-synapse
chown -R synapse:synapse /var/lib/matrix-synapse /var/log/matrix-synapse /etc/matrix-synapse

# Create systemd service
cat <<EOF >/etc/systemd/system/matrix-synapse.service
[Unit]
Description=Synapse Matrix homeserver
After=network.target

[Service]
Type=simple
User=synapse
Group=synapse
WorkingDirectory=/var/lib/matrix-synapse
ExecStart=/opt/venv/synapse/bin/python -m synapse.app.homeserver --config-path /etc/matrix-synapse/homeserver.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now matrix-synapse

# Wait for synapse to actually be ready on port 8008 (can take 30-60s on first run)
msg_info "Waiting for Synapse to start"
for i in $(seq 1 60); do
  if curl -sf http://localhost:8008/_matrix/client/versions >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
msg_ok "Synapse is ready"

$STD /opt/venv/synapse/bin/register_new_matrix_user \
  -a \
  --user admin \
  --password "$ADMIN_PASS" \
  --config /etc/matrix-synapse/homeserver.yaml \
  http://localhost:8008

{
  echo "Matrix-Credentials"
  echo "Admin username: admin"
  echo "Admin password: $ADMIN_PASS"
} >>~/matrix.creds

# The generated log config file path is correct, no need to remove it
# Just ensure the log file location is writable
touch /opt/homeserver.log
chown synapse:synapse /opt/homeserver.log

systemctl restart matrix-synapse
msg_ok "Installed Element Synapse"

fetch_and_deploy_gh_release "synapse-admin" "etkecc/synapse-admin" "tarball"

msg_info "Installing Synapse-Admin"
cd /opt/synapse-admin
$STD yarn global add serve
$STD yarn install --ignore-engines
$STD yarn build
mv ./dist ../ &&
  rm -rf * &&
  mv ../dist ./
msg_ok "Installed Synapse-Admin"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/synapse-admin.service
[Unit]
Description=Synapse-Admin Service
After=network.target
Requires=matrix-synapse.service

[Service]
Type=simple
WorkingDirectory=/opt/synapse-admin
ExecStart=/usr/local/bin/serve -s dist -l 5173
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now synapse-admin
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
