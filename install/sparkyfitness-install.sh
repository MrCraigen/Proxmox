#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tom Frenzel (tomfrenzel) | ARM64 port: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git \
  gnupg \
  ca-certificates \
  lsb-release \
  nginx \
  openssl \
  jq \
  xz-utils
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 22 LTS (arm64 binary)"
NODE_VER="22.16.0"
NODE_ARCHIVE="node-v${NODE_VER}-linux-arm64.tar.xz"
curl -fsSL "https://nodejs.org/dist/v${NODE_VER}/${NODE_ARCHIVE}" -o "/tmp/${NODE_ARCHIVE}"
tar -xJf "/tmp/${NODE_ARCHIVE}" -C /usr/local --strip-components=1
rm -f "/tmp/${NODE_ARCHIVE}"
msg_ok "Installed Node.js $(node -v)"

msg_info "Installing pnpm"
npm install -g pnpm &>/dev/null
msg_ok "Installed pnpm $(pnpm -v)"

msg_info "Installing PostgreSQL 15"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y postgresql-15
systemctl enable --now postgresql &>/dev/null
msg_ok "Installed PostgreSQL 15"

msg_info "Cloning SparkyFitness Repository"
LATEST=$(git ls-remote --tags --sort="v:refname" \
  https://github.com/CodeWithCJ/SparkyFitness.git \
  | grep -v '\^{}' | tail -1 | sed 's|.*refs/tags/||')
git clone --branch "$LATEST" --depth 1 \
  https://github.com/CodeWithCJ/SparkyFitness.git /opt/sparkyfitness &>/dev/null
echo "$LATEST" > /opt/sparkyfitness/.version
msg_ok "Cloned SparkyFitness ${LATEST}"

msg_info "Configuring Database"
PG_DB_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)"
PG_APP_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)"
sudo -u postgres psql -c "CREATE USER sparky WITH PASSWORD '${PG_DB_PASS}';" &>/dev/null
sudo -u postgres psql -c "CREATE DATABASE sparkyfitness OWNER sparky;" &>/dev/null
sudo -u postgres psql -d sparkyfitness -c "CREATE USER sparky_app WITH PASSWORD '${PG_APP_PASS}';" &>/dev/null
sudo -u postgres psql -d sparkyfitness -c "GRANT CONNECT ON DATABASE sparkyfitness TO sparky_app;" &>/dev/null
msg_ok "Configured Database"

msg_info "Configuring SparkyFitness"
LOCAL_IP=$(hostname -I | awk '{print $1}')
mkdir -p /etc/sparkyfitness /var/lib/sparkyfitness/uploads /var/lib/sparkyfitness/backup /var/www/sparkyfitness
cp /opt/sparkyfitness/docker/.env.example /etc/sparkyfitness/.env
sed \
  -i \
  -e "s|^#\?SPARKY_FITNESS_DB_HOST=.*|SPARKY_FITNESS_DB_HOST=localhost|" \
  -e "s|^#\?SPARKY_FITNESS_DB_PORT=.*|SPARKY_FITNESS_DB_PORT=5432|" \
  -e "s|^SPARKY_FITNESS_DB_NAME=.*|SPARKY_FITNESS_DB_NAME=sparkyfitness|" \
  -e "s|^SPARKY_FITNESS_DB_USER=.*|SPARKY_FITNESS_DB_USER=sparky|" \
  -e "s|^SPARKY_FITNESS_DB_PASSWORD=.*|SPARKY_FITNESS_DB_PASSWORD=${PG_DB_PASS}|" \
  -e "s|^SPARKY_FITNESS_APP_DB_USER=.*|SPARKY_FITNESS_APP_DB_USER=sparky_app|" \
  -e "s|^SPARKY_FITNESS_APP_DB_PASSWORD=.*|SPARKY_FITNESS_APP_DB_PASSWORD=${PG_APP_PASS}|" \
  -e "s|^SPARKY_FITNESS_SERVER_HOST=.*|SPARKY_FITNESS_SERVER_HOST=localhost|" \
  -e "s|^SPARKY_FITNESS_SERVER_PORT=.*|SPARKY_FITNESS_SERVER_PORT=3010|" \
  -e "s|^SPARKY_FITNESS_FRONTEND_URL=.*|SPARKY_FITNESS_FRONTEND_URL=http://${LOCAL_IP}:80|" \
  -e "s|^GARMIN_MICROSERVICE_URL=.*|GARMIN_MICROSERVICE_URL=http://${LOCAL_IP}:8000|" \
  -e "s|^SPARKY_FITNESS_API_ENCRYPTION_KEY=.*|SPARKY_FITNESS_API_ENCRYPTION_KEY=$(openssl rand -hex 32)|" \
  -e "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=$(openssl rand -hex 32)|" \
  /etc/sparkyfitness/.env
# Link env into server dir (tsx picks it up from cwd)
ln -sf /etc/sparkyfitness/.env /opt/sparkyfitness/SparkyFitnessServer/.env
msg_ok "Configured SparkyFitness"

msg_info "Building Backend"
cd /opt/sparkyfitness/SparkyFitnessServer
HUSKY=0 $STD pnpm install --ignore-scripts
msg_ok "Built Backend"

msg_info "Building Frontend (Patience)"
cd /opt/sparkyfitness
HUSKY=0 $STD pnpm install --ignore-scripts
cd /opt/sparkyfitness/SparkyFitnessFrontend
$STD pnpm run build
cp -a /opt/sparkyfitness/SparkyFitnessFrontend/dist/. /var/www/sparkyfitness/
msg_ok "Built Frontend"

msg_info "Creating SparkyFitness Service"
cat <<EOF >/etc/systemd/system/sparkyfitness-server.service
[Unit]
Description=SparkyFitness Backend Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/sparkyfitness/SparkyFitnessServer
EnvironmentFile=/etc/sparkyfitness/.env
ExecStart=/opt/sparkyfitness/SparkyFitnessServer/node_modules/.bin/tsx SparkyFitnessServer.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now sparkyfitness-server
msg_ok "Created SparkyFitness Service"

msg_info "Configuring Nginx"
sed \
  -e 's|${SPARKY_FITNESS_SERVER_HOST}|127.0.0.1|g' \
  -e 's|${SPARKY_FITNESS_SERVER_PORT}|3010|g' \
  -e 's|${NGINX_LISTEN_PORT}|80|g' \
  -e 's|${NGINX_ACCESS_LOG}|/var/log/nginx/sparkyfitness.access.log|g' \
  -e 's|${NGINX_ERROR_LOG}|/var/log/nginx/sparkyfitness.error.log|g' \
  -e 's|root /usr/share/nginx/html;|root /var/www/sparkyfitness;|g' \
  -e 's|server_name localhost;|server_name _;|g' \
  /opt/sparkyfitness/docker/nginx.conf >/etc/nginx/sites-available/sparkyfitness
ln -sf /etc/nginx/sites-available/sparkyfitness /etc/nginx/sites-enabled/sparkyfitness
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl enable -q --now nginx
$STD systemctl reload nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
