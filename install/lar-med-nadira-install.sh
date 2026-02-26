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

msg_info "Installing Node.js 22"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
  | tee /etc/apt/sources.list.d/nodesource.list >/dev/null
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

msg_info "Cloning Lar-med-Nadira"
$STD git clone https://github.com/asifma/lar-med-nadira /opt/lar-med-nadira
msg_ok "Cloned Repository"

msg_info "Installing npm Dependencies"
cd /opt/lar-med-nadira
$STD npm install
msg_ok "Installed npm Dependencies"

msg_info "Building Application (this may take a few minutes)"
cd /opt/lar-med-nadira
npm run build
msg_ok "Built Application"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/lar-med-nadira
server {
    listen 3000;
    server_name _;

    root /opt/lar-med-nadira/dist;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
ln -sf /etc/nginx/sites-available/lar-med-nadira /etc/nginx/sites-enabled/lar-med-nadira
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl enable -q --now nginx
msg_ok "Configured and Started Nginx"

motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned Up"
