#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://github.com/asifma/lar-med-nadira

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
  ca-certificates \
  gnupg \
  nginx
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 20"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
  | tee /etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

msg_info "Cloning Lär med Nadira"
git clone -q https://github.com/asifma/lar-med-nadira /opt/lar-med-nadira
cd /opt/lar-med-nadira
msg_ok "Cloned Repository"

msg_info "Installing npm Dependencies"
$STD npm install
msg_ok "Installed npm Dependencies"

msg_info "Building Application"
$STD npm run build
msg_ok "Built Application"

msg_info "Configuring Nginx"
cat <<'NGINX_CONF' >/etc/nginx/sites-available/lar-med-nadira
server {
    listen 3000;
    server_name _;

    root /opt/lar-med-nadira/dist;
    index index.html;

    # Enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # SPA fallback — send all routes to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX_CONF

ln -sf /etc/nginx/sites-available/lar-med-nadira /etc/nginx/sites-enabled/lar-med-nadira
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
msg_ok "Configured Nginx"

msg_info "Creating systemd Service"
cat <<'SYSTEMD_UNIT' >/etc/systemd/system/lar-med-nadira.service
[Unit]
Description=Lär med Nadira - Children's Learning App
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/nginx
ExecStop=/usr/sbin/nginx -s quit
ExecReload=/usr/sbin/nginx -s reload
PIDFile=/run/nginx.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT

systemctl enable -q --now lar-med-nadira
msg_ok "Created and Started Service"

motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned Up"
