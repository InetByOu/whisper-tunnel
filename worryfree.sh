#!/bin/bash
# worryfree.sh - Hysteria 2 one-click installer
# Port: 5667 (fixed) | Port hopping: 3000-19999 (fixed)
# No colors, plain text output

set -e

# ================ ROOT CHECK ================
echo "[1/9] Checking root privileges..."
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi
echo "OK"

# ================ CLEANUP ================
echo "[2/9] Cleaning previous installation..."
systemctl stop hysteria-server 2>/dev/null || true
systemctl disable hysteria-server 2>/dev/null || true
rm -rf /etc/hysteria
rm -f /usr/local/bin/hysteria
rm -f /etc/systemd/system/hysteria-server.service

# Hapus aturan DNAT lama
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"
iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :5667 2>/dev/null || true

# Reset UFW total
ufw --force disable 2>/dev/null || true
ufw --force reset 2>/dev/null || true
echo "Cleanup done."

# ================ UPDATE & DEPENDENCIES ================
echo "[3/9] Updating system and installing dependencies..."
apt update -y
apt upgrade -y
apt install -y curl wget openssl ufw iptables net-tools ca-certificates jq
echo "Dependencies installed."

# ================ INSTALL HYSTERIA 2 ================
echo "[4/9] Installing Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/)
echo "Hysteria 2 installed."

# ================ PROMPT KONFIGURASI ================
echo "[5/9] Configuration setup (port already set to 5667)..."

DEFAULT_AUTH="gstgg47e"
DEFAULT_OBFS="huhqb\`c"
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

# ================ GENERATE CERTIFICATE ================
echo "[6/9] Generating self-signed certificate (10 years)..."
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -days 3650 \
    -subj "/CN=$SNI" 2>/dev/null
echo "Certificate created."

# ================ CREATE CONFIG.YAML ================
echo "[7/9] Creating config.yaml..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :5667

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $AUTH_PASS

bandwidth:
  up: $BANDWIDTH mbps
  down: $BANDWIDTH mbps

obfs:
  type: salamander
  salamander:
    password: $OBFS_PASS

masquerade:
  type: proxy
  proxy:
    url: https://www.google.com/
    rewriteHost: true

log:
  level: info
EOF
echo "config.yaml created."

# ================ VALIDASI KONFIGURASI ================
echo "Validating Hysteria configuration..."
if /usr/local/bin/hysteria server -c /etc/hysteria/config.yaml --test-only 2>/dev/null; then
    echo "Configuration is valid."
else
    echo "ERROR: Hysteria configuration is invalid."
    exit 1
fi

# ================ DETEKSI INTERFACE ================
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"
echo "Using network interface: $IFACE"

# ================ CEK KETERSEDIAAN PORT ================
echo "Checking if port 5667 is available..."
if ss -uln | grep -q ":5667 "; then
    echo "WARNING: Port 5667 is already in use. Attempting to continue anyway..."
fi

# ================ IPTABLES DNAT ================
echo "[8/9] Adding DNAT rule for port hopping..."
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :5667
echo "DNAT rule added: UDP 3000-19999 -> :5667"

# ================ UFW CONFIGURATION ================
echo "[9/9] Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 5667/udp
ufw allow 3000:19999/udp
ufw --force enable
ufw status | grep -E "22|5667|3000:19999" || true
echo "UFW configured."

# ================ IP FORWARDING ================
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# ================ START HYSTERIA ================
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

# Beri waktu untuk start
sleep 3

# Cek status dengan detail
if systemctl is-active --quiet hysteria-server; then
    echo "Hysteria service is running."
else
    echo "ERROR: Hysteria service failed to start."
    echo "--- Last 20 lines of journal ---"
    journalctl -u hysteria-server -n 20 --no-pager
    echo ""
    echo "--- Checking binary and permissions ---"
    ls -la /usr/local/bin/hysteria
    file /usr/local/bin/hysteria
    echo ""
    echo "--- Checking config file ---"
    cat /etc/hysteria/config.yaml | grep -v password
    echo ""
    echo "--- Checking if port is already in use ---"
    ss -ulpn | grep 5667 || echo "Port 5667 is free"
    echo ""
    echo "Please fix the error manually and run: systemctl restart hysteria-server"
    exit 1
fi

# ================ GENERATE CLIENT URI ================
echo "Generating client URIs..."

PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 icanhazip.com || curl -s --connect-timeout 5 ipinfo.io/ip)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="YOUR_SERVER_IP"

read -p "Enter domain (optional, press Enter for IP $PUBLIC_IP): " DOMAIN
SERVER_ADDR=${DOMAIN:-$PUBLIC_IP}

# URL encode backtick
OBFS_ENC=$(echo "$OBFS_PASS" | sed 's/`/%60/g')
AUTH_ENC=$(echo "$AUTH_PASS" | sed 's/`/%60/g')

URI="hysteria2://$AUTH_ENC@$SERVER_ADDR:5667?insecure=1&obfs=salamander&obfs-password=$OBFS_ENC&sni=$SNI"
URI_HOPPING="hysteria2://$AUTH_ENC@$SERVER_ADDR:3000-19999?insecure=1&obfs=salamander&obfs-password=$OBFS_ENC&sni=$SNI"

# ================ SUMMARY ================
echo ""
echo "====================================================="
echo "     HYSTERIA 2 INSTALLATION COMPLETE"
echo "====================================================="
echo ""
echo "Server Address   : $SERVER_ADDR"
echo "Port (fixed)     : 5667/udp"
echo "Hopping Range    : 3000-19999/udp"
echo "Auth Password    : $AUTH_PASS"
echo "Obfs Password    : $OBFS_PASS"
echo "SNI              : $SNI"
echo "Bandwidth        : $BANDWIDTH Mbps"
echo ""
echo "--- CLIENT URI (STANDARD) ---"
echo "$URI"
echo ""
echo "--- CLIENT URI (PORT HOPPING) ---"
echo "$URI_HOPPING"
echo ""
echo "--- UFW RULES ---"
ufw status numbered | grep -E "22|5667|3000:19999" || true
echo ""
echo "--- DNAT RULE ---"
iptables -t nat -L PREROUTING -v | grep "dpt:3000-19999" || echo "Rule active"
echo ""
echo "Installation successful!"
echo "====================================================="

exit 0
