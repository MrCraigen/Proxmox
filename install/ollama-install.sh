#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: MrCraigen
# License: MIT | https://github.com/MrCraigen/Proxmox/raw/main/LICENSE
# Source: https://ollama.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl tar
msg_ok "Installed Dependencies"

msg_info "Installing Ollama (ARM64)"
LATEST=$(curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -fsSL "https://github.com/ollama/ollama/releases/download/${LATEST}/ollama-linux-arm64.tar.gz" \
  | tar -xz -C /usr/local
msg_ok "Installed Ollama ${LATEST}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=root
Group=root
Restart=always
RestartSec=3
Environment=OLLAMA_HOST=0.0.0.0:11434
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ollama
msg_ok "Created Service"

msg_info "Creating MOTD"
cat <<'EOF' >/etc/motd

╔══════════════════════════════════════════════════════════╗
║                  Ollama AI - ARM64                       ║
╠══════════════════════════════════════════════════════════╣
║  API   : http://<CT-IP>:11434                            ║
║  Compat: http://<CT-IP>:11434/v1/chat/completions        ║
╠══════════════════════════════════════════════════════════╣
║  PULL A MODEL (run inside this LXC):                     ║
║   ollama pull gemma3:12b      (~8GB, recommended)        ║
║   ollama pull mistral:7b      (~4GB, fast)               ║
║   ollama pull llama3.2:3b     (~2GB, very fast)          ║
║   ollama pull qwen2.5:7b      (~4GB, great for code)     ║
║   ollama pull phi4:14b        (~9GB, very capable)       ║
╠══════════════════════════════════════════════════════════╣
║  USAGE EXAMPLE:                                          ║
║   baseURL: "http://<CT-IP>:11434/v1"                     ║
║   apiKey:  "ollama"  (any string)                        ║
║   model:   "gemma3:12b"                                  ║
╠══════════════════════════════════════════════════════════╣
║  SERVICE:                                                ║
║   systemctl status ollama                                ║
║   systemctl restart ollama                               ║
║   journalctl -u ollama -f                                ║
╚══════════════════════════════════════════════════════════╝

EOF
msg_ok "Created MOTD"

motd_ssh
customize
cleanup_lxc
