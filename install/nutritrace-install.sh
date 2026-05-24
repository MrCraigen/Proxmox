#!/usr/bin/env bash
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
# Copyright (c) 2021-2026 MrCraigen
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/TraceApps/nutritrace

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
  python3 \
  make \
  g++ \
  openssl \
  ca-certificates
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 20 (ARM64)"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

msg_info "Cloning NutriTrace Repository"
git clone --depth=1 https://github.com/TraceApps/nutritrace.git /opt/nutritrace &>/dev/null
msg_ok "Cloned NutriTrace Repository"

msg_info "Building Frontend (Svelte/Vite)"
cd /opt/nutritrace
$STD npm install
$STD npm run build
# Mirror what the Dockerfile does: COPY --from=build /app/dist ./dist
# The Express server serves static files from ./dist relative to its own directory
cp -r /opt/nutritrace/dist /opt/nutritrace/server/dist
msg_ok "Built Frontend"

msg_info "Installing Server Dependencies"
cd /opt/nutritrace/server
$STD npm install --omit=dev
msg_ok "Installed Server Dependencies"

msg_info "Configuring Data Directories"
mkdir -p /opt/nutritrace-data/db
mkdir -p /opt/nutritrace-data/uploads
msg_ok "Created Data Directories"

msg_info "Generating JWT Secret"
JWT_SECRET=$(openssl rand -base64 48)
msg_ok "Generated JWT Secret"

msg_info "Creating Environment File"
cat <<EOF >/opt/nutritrace/server/.env
DB_PATH=/opt/nutritrace-data/db/nutritrace.db
UPLOADS_PATH=/opt/nutritrace-data/uploads
JWT_SECRET=${JWT_SECRET}
# Required for plain-HTTP LXC installs — allows auth cookies to be sent without HTTPS.
# Only safe on a trusted local network. Remove if you add a reverse proxy with TLS.
INSECURE_COOKIES=1
# Optional SMTP (for password reset & user invites)
# SMTP_HOST=smtp.example.com
# SMTP_PORT=587
# SMTP_SECURE=false
# SMTP_USER=you@example.com
# SMTP_PASS=your-password
# SMTP_FROM=NutriTrace <noreply@example.com>
# Optional AI (Claude, OpenAI, or Gemini — bring your own key)
# AI_PROVIDER=claude
# AI_API_KEY=your-api-key
# AI_MODEL=claude-haiku-4-5-20251001
# AI_ENABLED=true
EOF
msg_ok "Created Environment File"

msg_info "Creating Systemd Service"
cat <<'EOF' >/etc/systemd/system/nutritrace.service
[Unit]
Description=NutriTrace — Self-hosted Nutrition Tracker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nutritrace/server
EnvironmentFile=/opt/nutritrace/server/.env
ExecStart=/usr/bin/node index.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nutritrace

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Systemd Service"

msg_info "Configuring Cookie Security for HTTP"
# NutriTrace defaults to secure (HTTPS-only) cookies. Since LXC installs run over
# plain HTTP on the local network, INSECURE_COOKIES=1 is set in the .env above.
msg_ok "Configured Cookie Security"

msg_info "Enabling and Starting NutriTrace"
systemctl enable -q nutritrace
systemctl start nutritrace
msg_ok "Started NutriTrace"

motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned Up"
