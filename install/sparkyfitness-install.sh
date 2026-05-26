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
  ca-certificates \
  gnupg \
  lsb-release \
  sudo \
  mc
msg_ok "Installed Dependencies"

msg_info "Installing Docker (ARM64)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

$STD apt-get update
$STD apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
msg_ok "Installed Docker (ARM64)"

msg_info "Setting Up SparkyFitness"
mkdir -p /opt/sparkyfitness
cd /opt/sparkyfitness

# Generate secure random passwords and secrets
DB_PASSWORD=$(openssl rand -hex 16)
APP_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
ADMIN_PASSWORD=$(openssl rand -hex 8)

# Write docker-compose.yml
cat > /opt/sparkyfitness/docker-compose.yml << 'COMPOSE'
services:
  sparkyfitness-db:
    image: postgres:15-alpine
    container_name: sparkyfitness-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${SPARKY_FITNESS_DB_NAME}
      POSTGRES_USER: ${SPARKY_FITNESS_DB_USER}
      POSTGRES_PASSWORD: ${SPARKY_FITNESS_DB_PASSWORD}
    volumes:
      - /opt/sparkyfitness/postgresql:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${SPARKY_FITNESS_DB_USER} -d ${SPARKY_FITNESS_DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5

  sparkyfitness-server:
    image: codewithcj/sparkyfitness_server:latest
    container_name: sparkyfitness-server
    restart: unless-stopped
    depends_on:
      sparkyfitness-db:
        condition: service_healthy
    environment:
      SPARKY_FITNESS_LOG_LEVEL: ${SPARKY_FITNESS_LOG_LEVEL}
      SPARKY_FITNESS_DB_USER: ${SPARKY_FITNESS_DB_USER}
      SPARKY_FITNESS_DB_HOST: sparkyfitness-db
      SPARKY_FITNESS_DB_NAME: ${SPARKY_FITNESS_DB_NAME}
      SPARKY_FITNESS_DB_PASSWORD: ${SPARKY_FITNESS_DB_PASSWORD}
      SPARKY_FITNESS_APP_DB_USER: ${SPARKY_FITNESS_APP_DB_USER}
      SPARKY_FITNESS_APP_DB_PASSWORD: ${SPARKY_FITNESS_APP_DB_PASSWORD}
      SPARKY_FITNESS_API_ENCRYPTION_KEY: ${SPARKY_FITNESS_API_ENCRYPTION_KEY}
      SPARKY_FITNESS_JWT_SECRET: ${SPARKY_FITNESS_JWT_SECRET}
      SPARKY_FITNESS_FRONTEND_URL: ${SPARKY_FITNESS_FRONTEND_URL}
    volumes:
      - /opt/sparkyfitness/server-data:/app/data

  sparkyfitness-frontend:
    image: codewithcj/sparkyfitness:latest
    container_name: sparkyfitness-frontend
    restart: unless-stopped
    depends_on:
      - sparkyfitness-server
    ports:
      - "3004:80"
    environment:
      SPARKY_FITNESS_SERVER_URL: ${SPARKY_FITNESS_SERVER_URL}
COMPOSE

# Write .env file
cat > /opt/sparkyfitness/.env << EOF
# Database
SPARKY_FITNESS_DB_NAME=sparkyfitness_db
SPARKY_FITNESS_DB_USER=sparky_admin
SPARKY_FITNESS_DB_PASSWORD=${DB_PASSWORD}

# App DB user (used by the server at runtime)
SPARKY_FITNESS_APP_DB_USER=sparky_app
SPARKY_FITNESS_APP_DB_PASSWORD=${APP_DB_PASSWORD}

# Server
SPARKY_FITNESS_LOG_LEVEL=info
SPARKY_FITNESS_API_ENCRYPTION_KEY=${ENCRYPTION_KEY}
SPARKY_FITNESS_JWT_SECRET=${JWT_SECRET}

# URLs (update IP_ADDRESS after install if needed)
SPARKY_FITNESS_FRONTEND_URL=http://localhost:3004
SPARKY_FITNESS_SERVER_URL=http://sparkyfitness-server:3010
EOF

chmod 600 /opt/sparkyfitness/.env
msg_ok "Configured SparkyFitness"

msg_info "Pulling Docker Images (ARM64 — this may take a few minutes)"
cd /opt/sparkyfitness
docker compose pull &>/dev/null
msg_ok "Pulled Docker Images"

msg_info "Starting SparkyFitness"
docker compose up -d &>/dev/null
msg_ok "Started SparkyFitness"

msg_info "Creating Credential File"
cat > /opt/sparkyfitness/credentials.txt << EOF
=== SparkyFitness Credentials ===
Frontend URL : http://localhost:3004
DB Password  : ${DB_PASSWORD}
App DB Pass  : ${APP_DB_PASSWORD}
JWT Secret   : ${JWT_SECRET}
Encryption   : ${ENCRYPTION_KEY}

Manage stack : cd /opt/sparkyfitness && docker compose [up -d | down | logs | pull]
EOF
chmod 600 /opt/sparkyfitness/credentials.txt
msg_ok "Credential File Saved to /opt/sparkyfitness/credentials.txt"

motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned Up"
