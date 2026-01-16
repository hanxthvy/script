#!/usr/bin/env bash
set -euo pipefail

### ===== INPUT =====
FQDN="${1:-${WINGS_FQDN:-}}"
PANEL_URL="${PANEL_URL:-}"
TOKEN="${WINGS_TOKEN:-}"
NODE_ID="${WINGS_NODE_ID:-}"

[ -z "$FQDN" ] && echo "FQDN required" && exit 1
[ "$EUID" -ne 0 ] && echo "run as root" && exit 1

export DEBIAN_FRONTEND=noninteractive

### ===== OS =====
. /etc/os-release
case "$ID" in ubuntu|debian) ;; *) exit 1 ;; esac

### ===== ARCH =====
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) exit 1 ;;
esac

### ===== DEPS =====
apt update -y
apt install -y curl ca-certificates ufw certbot

### ===== FIREWALL =====
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 8080
ufw --force enable

### ===== DOCKER =====
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

### ===== SSL =====
certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --register-unsafely-without-email \
  -d "$FQDN"

### ===== WINGS =====
curl -L \
  "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}" \
  -o /usr/local/bin/wings
chmod +x /usr/local/bin/wings

mkdir -p /etc/pterodactyl /var/lib/pterodactyl

### ===== SYSTEMD (UPSTREAM-LIKE) =====
cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096
LimitNPROC=4096
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable wings

### ===== AUTO DEPLOY CONFIG =====
if [ -n "$PANEL_URL" ] && [ -n "$TOKEN" ] && [ -n "$NODE_ID" ]; then
  /usr/local/bin/wings configure \
    --panel-url "$PANEL_URL" \
    --token "$TOKEN" \
    --node "$NODE_ID"
  systemctl restart wings
fi

echo "DONE"
