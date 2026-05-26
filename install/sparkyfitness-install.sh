#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

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
  git \
  gnupg \
  ca-certificates \
  lsb-release \
  nginx \
  openssl \
  sudo \
  xz-utils
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 22 LTS (arm64 binary)"
NODE_VER="22.16.0"
NODE_ARCHIVE="node-v${NODE_VER}-linux-arm64.tar.xz"
curl -fsSL "https://nodejs.org/dist/v${NODE_VER}/${NODE_ARCHIVE}" -o "/tmp/${NODE_ARCHIVE}"
tar -xJf "/tmp/${NODE_ARCHIVE}" -C /usr/local --strip-components=1
rm -f "/tmp/${NODE_ARCHIVE}"
msg_ok "Installed Node.js $(node -v)"

msg_info "Installing PostgreSQL 15"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y postgresql-15
msg_ok "Installed PostgreSQL 15"

msg_info "Cloning SparkyFitness Repository"
LATEST=$(curl -fsSL "https://api.github.com/repos/CodeWithCJ/SparkyFitness/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')
git clone --branch "$LATEST" --depth 1 \
  https://github.com/CodeWithCJ/SparkyFitness.git /opt/SparkyFitness &>/dev/null
echo "$LATEST" > /opt/SparkyFitness/.version
msg_ok "Cloned SparkyFitness ${LATEST}"

msg_info "Configuring PostgreSQL"
DB_NAME="sparky"
DB_USER="sparkyuser"
DB_PASS="$(openssl rand -hex 16)"
APP_DB_USER="sparkyappuser"
APP_DB_PASS="$(openssl rand -hex 16)"

systemctl enable --now postgresql &>/dev/null

sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" &>/dev/null
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" &>/dev/null
sudo -u postgres psql -d "${DB_NAME}" -c "CREATE USER ${APP_DB_USER} WITH PASSWORD '${APP_DB_PASS}';" &>/dev/null
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT CONNECT ON DATABASE ${DB_NAME} TO ${APP_DB_USER};" &>/dev/null
msg_ok "Configured PostgreSQL"

msg_info "Configuring Environment"
API_KEY="$(openssl rand -hex 32)"
JWT_SECRET="$(openssl rand -hex 32)"
IP=$(hostname -I | awk '{print $1}')

cat > /opt/SparkyFitness/.env << EOF
# Database
SPARKY_FITNESS_DB_HOST=localhost
SPARKY_FITNESS_DB_PORT=5432
SPARKY_FITNESS_DB_NAME=${DB_NAME}
SPARKY_FITNESS_DB_USER=${DB_USER}
SPARKY_FITNESS_DB_PASSWORD=${DB_PASS}
SPARKY_FITNESS_APP_DB_USER=${APP_DB_USER}
SPARKY_FITNESS_APP_DB_PASSWORD=${APP_DB_PASS}

# Application
SPARKY_FITNESS_API_ENCRYPTION_KEY=${API_KEY}
SPARKY_FITNESS_JWT_SECRET=${JWT_SECRET}
SPARKY_FITNESS_FRONTEND_URL=http://${IP}:8080
SPARKY_FITNESS_LOG_LEVEL=info

# Server
PORT=3010
NODE_ENV=production
EOF
msg_ok "Configured Environment"

msg_info "Installing Server Dependencies"
cd /opt/SparkyFitness/SparkyFitnessServer
cp /opt/SparkyFitness/.env .env
$STD npm ci --omit=dev
msg_ok "Installed Server Dependencies"

msg_info "Building Frontend"
cd /opt/SparkyFitness/SparkyFitnessFrontend
cp /opt/SparkyFitness/.env .env
cat > .env.production << EOF
VITE_API_URL=http://${IP}:3010
EOF
$STD npm ci
$STD npm run build
mkdir -p /var/www/sparkyfitness
cp -r dist/* /var/www/sparkyfitness/
msg_ok "Built Frontend"

msg_info "Detecting Server Entry Point"
SERVER_ENTRY="server.js"
for f in server.js index.js app.js src/server.js src/index.js; do
  if [[ -f "/opt/SparkyFitness/SparkyFitnessServer/${f}" ]]; then
    SERVER_ENTRY="$f"
    break
  fi
done
# Also check package.json "main" field
PKG_MAIN=$(node -e "try{const p=require('/opt/SparkyFitness/SparkyFitnessServer/package.json');console.log(p.main||'')}catch(e){}" 2>/dev/null)
[[ -n "$PKG_MAIN" && -f "/opt/SparkyFitness/SparkyFitnessServer/${PKG_MAIN}" ]] && SERVER_ENTRY="$PKG_MAIN"
msg_ok "Server entry point: ${SERVER_ENTRY}"

msg_info "Creating systemd Service"
cat > /etc/systemd/system/sparkyfitness-server.service << EOF
[Unit]
Description=SparkyFitness Backend Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/SparkyFitness/SparkyFitnessServer
EnvironmentFile=/opt/SparkyFitness/.env
ExecStart=/usr/local/bin/node ${SERVER_ENTRY}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sparkyfitness-server

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now sparkyfitness-server &>/dev/null
msg_ok "Created and Started sparkyfitness-server Service"

msg_info "Configuring Nginx"
cat > /etc/nginx/sites-available/sparkyfitness << EOF
server {
    listen 8080;
    server_name _;

    root /var/www/sparkyfitness;
    index index.html;

    client_max_body_size 50M;

    # Serve frontend SPA
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Proxy API requests to backend
    location /api/ {
        proxy_pass http://127.0.0.1:3010;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/sparkyfitness /etc/nginx/sites-enabled/sparkyfitness
$STD nginx -t
systemctl enable --now nginx &>/dev/null
msg_ok "Configured Nginx"

msg_info "Saving Credentials"
cat > /root/.sparkyfitness_credentials << EOF
SparkyFitness Credentials
=========================
DB Name:          ${DB_NAME}
DB Admin User:    ${DB_USER}
DB Admin Pass:    ${DB_PASS}
DB App User:      ${APP_DB_USER}
DB App Pass:      ${APP_DB_PASS}
API Encrypt Key:  ${API_KEY}
JWT Secret:       ${JWT_SECRET}
Frontend URL:     http://${IP}:8080
Backend Port:     3010
EOF
chmod 600 /root/.sparkyfitness_credentials
msg_ok "Credentials saved to /root/.sparkyfitness_credentials"

motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned Up"
