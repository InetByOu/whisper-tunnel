#!/bin/bash
# worryfree.sh - Hysteria 2 one-click installer (fixed version)
# Port: 5667 (fixed) | Hopping: 3000-19999 via nftables DNAT
# No colors, plain text, Ubuntu 24.04 compatible

set -e

echo "[1/10] Checking root privileges..."
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi
echo "OK"

# Cleanup lama
echo "[2/10] Cleaning previous installation..."
systemctl stop hysteria-server 2>/dev/null || true
systemctl disable hysteria-server 2>/dev/null || true
rm -rf /etc/hysteria
rm -f /usr/local/bin/hysteria
rm -f /etc/systemd/system/hysteria-server.service
rm -f /etc/nftables.conf

nft flush ruleset 2>/dev/null || true
systemctl restart nftables 2>/dev/null || true

echo "Cleanup done."

# Update & deps (hilangkan ufw, pakai nftables)
echo "[3/10] Updating system and installing dependencies..."
apt update -y
apt upgrade -y
apt install -y curl wget openssl nftables net-tools ca-certificates jq
echo "Dependencies installed."

# Install Hysteria 2
echo "[4/10] Installing Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/)
echo "Hysteria 2 installed."

# Konfigurasi
echo "[5/10] Configuration setup (port fixed 5667)..."

DEFAULT_AUTH="gstgg47e"
DEFAULT_OBFS="hu``hqb`c"
DEFAULT_SNI="graph.facebook.com"
DEFAULT_BW="100"

read -p "Enter authentication password [$DEFAULT_AUTH]: " AUTH_PASS
AUTH_PASS=${AUTH_PASS:-$DEFAULT_AUTH}

read -p "Enter obfuscation password (salamander) [$DEFAULT_OBFS]: " OBFS_PASS
OBFS_PASS=${OBFS_PASS:-$DEFAULT_OBFS}

read -p "Enter SNI/server_name [$DEFAULT_SNI]: " SNI
SNI=${SNI:-$DEFAULT_SNI}

read -p "Enter bandwidth up/down (Mbps) [$DEFAULT_BW]: " BANDWIDTH
BANDWIDTH=${BANDWIDTH:-$DEFAULT_BW}

echo "Configuration set."

# Generate cert
echo "[6/10] Generating self-signed certificate..."
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -days 3650 \
    -subj "/CN=$SNI" 2>/dev/null
chmod 600 /etc/hysteria/server.key
echo "Certificate created."

# Config.yaml
echo "[7/10] Creating config.yaml..."
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
echo "config.yaml created."

# Test config
echo "[8/10] Validating configuration..."
if hysteria server -c /etc/hysteria/config.yaml --test-only; then
    echo "Configuration is valid."
else
    echo "ERROR: Configuration invalid. Check logs below."
    hysteria server -c /etc/hysteria/config.yaml --test-only || true
    exit 1
fi

# Interface
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"
echo "Using interface: $IFACE"

# nftables DNAT + allow
echo "[9/10] Setting up nftables (DNAT + firewall)..."
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
        ct state established,related accept
        iif lo accept
        tcp dport 22 accept
        udp dport 5667 accept
        udp dport 3000-19999 accept
    }
    chain forward { type filter hook forward priority 0; policy accept; }
    chain output { type filter hook output priority 0; policy accept; }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport 3000-19999 dnat to :5667
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "$IFACE" masquerade
    }
}
EOF

nft -f /etc/nftables.conf
systemctl enable nftables
systemctl restart nftables
echo "nftables applied. Check: sudo nft list ruleset"

# IP forwarding
sysctl -w net.ipv4.ip_forward=1
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Start service
echo "[10/10] Starting Hysteria 2 service..."
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

sleep 5  # beri waktu lebih

if systemctl is-active --quiet hysteria-server; then
    echo "Hysteria service is running successfully."
else
    echo "ERROR: Hysteria service failed to start. Debugging info:"
    echo "--- journalctl last 30 lines ---"
    journalctl -u hysteria-server -n 30 --no-pager
    echo ""
    echo "--- Manual start test ---"
    /usr/local/bin/hysteria server -c /etc/hysteria/config.yaml || true
    echo ""
    echo "--- Port check ---"
    ss -tuln | grep 5667 || echo "Port 5667 not bound"
    echo ""
    echo "Fix suggestions:"
    echo "1. Check if port 5667 in use: sudo kill \$(sudo lsof -t -i:5667)"
    echo "2. Re-run manual: sudo hysteria server -c /etc/hysteria/config.yaml"
    echo "3. Check cert permission: ls -l /etc/hysteria"
    exit 1
fi

# Client URI
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")
read -p "Enter domain (optional, or Enter for IP $PUBLIC_IP): " DOMAIN
SERVER_ADDR=${DOMAIN:-$PUBLIC_IP}

URI="hysteria2://$AUTH_PASS@$SERVER_ADDR:5667/?obfs=salamander&obfs-password=$OBFS_PASS&sni=$SNI&insecure=1"
URI_HOP="hysteria2://$AUTH_PASS@$SERVER_ADDR:3000-19999/?obfs=salamander&obfs-password=$OBFS_PASS&sni=$SNI&insecure=1"

echo ""
echo "====================================================="
echo "     HYSTERIA 2 INSTALLATION COMPLETE"
echo "====================================================="
echo "Server Address   : $SERVER_ADDR"
echo "Port Internal    : 5667/udp"
echo "Hopping Range    : 3000-19999/udp (via nftables DNAT)"
echo "Auth Password    : $AUTH_PASS"
echo "Obfs Password    : $OBFS_PASS"
echo "SNI              : $SNI"
echo "Bandwidth        : $BANDWIDTH Mbps"
echo ""
echo "Client URI (standard): $URI"
echo "Client URI (hopping) : $URI_HOP"
echo ""
echo "Check nftables rules: sudo nft list ruleset"
echo "Check service status: sudo systemctl status hysteria-server"
echo "View logs: journalctl -u hysteria-server -e -f"
echo "====================================================="
echo "Installation successful! Test client connection now."
