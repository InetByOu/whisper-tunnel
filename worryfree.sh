#!/bin/bash
# update-hysteria2.sh - Hysteria 2 updater (selalu ganti yang lama dengan baru)
# Inspired by Zivpn UDP installer style
# Selalu overwrite: binary, cert, config, service file

echo "Updating Hysteria 2 server (overwrite all existing files)..."

# 1. Update sistem
sudo apt-get update && sudo apt-get upgrade -y

# 2. Stop & disable service lama
systemctl stop hysteria-server 1> /dev/null 2> /dev/null
systemctl disable hysteria-server 1> /dev/null 2> /dev/null

# 3. Hapus file lama sepenuhnya
rm -f /usr/local/bin/hysteria
rm -rf /etc/hysteria
rm -f /etc/systemd/system/hysteria-server.service

# Flush nftables & iptables lama
nft flush ruleset 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true

echo "All old files removed. Starting fresh install/update..."

# 4. Download Hysteria 2 binary terbaru (overwrite)
echo "Downloading latest Hysteria 2 binary..."
wget https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 -O /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

# 5. Buat folder config baru
mkdir -p /etc/hysteria

# 6. Generate certificate baru (overwrite)
echo "Generating new self-signed certificate..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=graph.facebook.com"
chmod 644 /etc/hysteria/server.crt
chmod 644 /etc/hysteria/server.key
chown root:root /etc/hysteria/*

# 7. Prompt konfigurasi (seperti contoh Zivpn)
echo ""
echo "Hysteria 2 Configuration"
DEFAULT_AUTH="gstgg47e"
DEFAULT_OBFS="hu``hqb`c"
DEFAULT_BW="100"

read -p "Enter authentication password [default: $DEFAULT_AUTH]: " AUTH_PASS
AUTH_PASS=${AUTH_PASS:-$DEFAULT_AUTH}

read -p "Enter obfuscation password (salamander) [default: $DEFAULT_OBFS]: " OBFS_PASS
OBFS_PASS=${OBFS_PASS:-$DEFAULT_OBFS}

read -p "Enter bandwidth up/down Mbps [default: $DEFAULT_BW]: " BANDWIDTH
BANDWIDTH=${BANDWIDTH:-$DEFAULT_BW}

# 8. Buat config.yaml baru (overwrite)
echo "Creating new config.yaml..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :5667

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $AUTH_PASS

bandwidth:
  up: ${BANDWIDTH} mbps
  down: ${BANDWIDTH} mbps

obfs:
  type: salamander
  salamander:
    password: "$OBFS_PASS"

masquerade:
  type: proxy
  proxy:
    url: https://www.google.com/
    rewriteHost: true

log:
  level: info
EOF

# 9. Buat systemd service baru (overwrite)
echo "Creating new systemd service file..."
cat <<EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3
Environment=HYSTERIA_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 10. Set capability & fix permission binary
setcap cap_net_bind_service=+ep /usr/local/bin/hysteria 2>/dev/null || true

# 11. Reload systemd & start service
systemctl daemon-reload
systemctl enable hysteria-server
systemctl start hysteria-server

sleep 5

# 12. Re-apply DNAT (overwrite rule lama)
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"

iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :5667

# UFW allow (jika masih pakai ufw)
ufw allow 5667/udp 2>/dev/null || true
ufw allow 3000:19999/udp 2>/dev/null || true
ufw reload 2>/dev/null || true

# 13. Cek status & log
echo ""
echo "=== Hysteria 2 status setelah update ==="
systemctl status hysteria-server -l

echo ""
echo "=== Log terakhir ==="
journalctl -u hysteria-server -n 20 --no-pager

echo ""
echo "Hysteria 2 telah di-update sepenuhnya dengan file baru!"
echo "Server address: $(curl -s ifconfig.me)"
echo "Port internal: 5667"
echo "Hopping range: 3000-19999"
echo "Auth: $AUTH_PASS"
echo "Obfs: $OBFS_PASS"
echo ""
echo "URI contoh (hopping): hysteria2://$AUTH_PASS@YOUR_IP:3000-19999/?obfs=salamander&obfs-password=$OBFS_PASS&sni=graph.facebook.com&insecure=1"
echo ""
echo "Jika masih error, jalankan manual: sudo /usr/local/bin/hysteria server -c /etc/hysteria/config.yaml"
echo "Update selesai!"
