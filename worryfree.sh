#!/bin/bash
# worryfree.sh - Hysteria 2 installer with port hopping (UFW + iptables DNAT)
# No colors, plain text output

set -e

# ================ ROOT CHECK ================
echo "[1/14] Checking root privileges..."
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi
echo "OK"

# ================ CLEANUP ================
echo "[2/14] Cleaning previous installation..."

# Stop and disable service
systemctl stop hysteria-server 2>/dev/null || true
systemctl disable hysteria-server 2>/dev/null || true

# Remove files
rm -rf /etc/hysteria
rm -f /usr/local/bin/hysteria
rm -f /etc/systemd/system/hysteria-server.service

# Remove old DNAT rules
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$INTERFACE" ] && INTERFACE="eth0"
iptables -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :5667 2>/dev/null || true

# Reset UFW completely
ufw --force disable 2>/dev/null || true
ufw --force reset 2>/dev/null || true

echo "Cleanup done."

# ================ SYSTEM UPDATE ================
echo "[3/14] Updating system..."
apt update -y && apt upgrade -y && apt autoremove -y
echo "System updated."

# ================ DEPENDENCIES ================
echo "[4/14] Installing dependencies..."
apt install -y curl wget openssl ufw iptables net-tools ca-certificates jq
echo "Dependencies installed."

# ================ INSTALL HYSTERIA 2 ================
echo "[5/14] Installing Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/)
echo "Hysteria 2 installed."

# ================ PROMPT CONFIG ================
echo "[6/14] Configuration setup..."

DEFAULT_PORT="5667"
DEFAULT_AUTH="gstgg47e"
DEFAULT_OBFS="huhqb\`c"
DEFAULT_SNI="graph.facebook.com"
DEFAULT_BW="100"

read -p "Enter Hysteria port [$DEFAULT_PORT]: " HY_PORT
HY_PORT=${HY_PORT:-$DEFAULT_PORT}

read -p "Enter auth password [$DEFAULT_AUTH]: " AUTH_PASS
AUTH_PASS=${AUTH_PASS:-$DEFAULT_AUTH}

read -p "Enter obfs password (salamander) [$DEFAULT_OBFS]: " OBFS_PASS
OBFS_PASS=${OBFS_PASS:-$DEFAULT_OBFS}

read -p "Enter SNI [$DEFAULT_SNI]: " SNI
SNI=${SNI:-$DEFAULT_SNI}

read -p "Enter bandwidth (Mbps) [$DEFAULT_BW]: " BANDWIDTH
BANDWIDTH=${BANDWIDTH:-$DEFAULT_BW}

echo "Configuration set."

# ================ GENERATE CERT ================
echo "[7/14] Generating self-signed certificate (10 years)..."
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -days 3650 \
    -subj "/CN=$SNI" 2>/dev/null
echo "Certificate created."

# ================ CONFIG.YAML ================
echo "[8/14] Creating config.yaml..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :$HY_PORT

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

# ================ DETECT INTERFACE ================
echo "[9/14] Detecting default network interface..."
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
    echo "Warning: Using fallback interface eth0"
else
    echo "Interface detected: $INTERFACE"
fi

# ================ IPTABLES DNAT ================
echo "[10/14] Adding DNAT rule for port hopping..."
iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :$HY_PORT
echo "DNAT rule added: UDP 3000-19999 -> :$HY_PORT"

# ================ UFW CONFIGURATION ================
echo "[11/14] Configuring UFW..."

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp

# Allow Hysteria main port
ufw allow $HY_PORT/udp

# Allow port hopping range - FORMAT YANG TERBUKTI BERHASIL
ufw allow 3000:19999/udp

# Enable UFW
ufw --force enable

# Show status
ufw status | grep -E "22|$HY_PORT|3000:19999" || true
echo "UFW configured."

# ================ IP FORWARDING ================
echo "[12/14] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# ================ START HYSTERIA ================
echo "[13/14] Starting Hysteria service..."
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

sleep 2
if systemctl is-active --quiet hysteria-server; then
    echo "Hysteria service is running."
else
    echo "Error: Hysteria service failed to start."
    exit 1
fi

# ================ SAVE IPTABLES ================
echo "[14/14] Saving iptables rules..."
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4
echo "Rules saved."

# ================ GENERATE URI ================
echo "Generating client URI..."

# Get public IP
PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 icanhazip.com || curl -s --connect-timeout 5 ipinfo.io/ip)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="YOUR_SERVER_IP"
    echo "Warning: Could not detect public IP."
fi

read -p "Enter domain (optional, press Enter for IP $PUBLIC_IP): " DOMAIN
SERVER_ADDR=${DOMAIN:-$PUBLIC_IP}

# URL encode for special characters (especially backtick)
OBFS_ENC=$(printf "%s" "$OBFS_PASS" | sed 's/`/%60/g')
AUTH_ENC=$(printf "%s" "$AUTH_PASS" | sed 's/`/%60/g')

URI="hysteria2://$AUTH_ENC@$SERVER_ADDR:$HY_PORT?insecure=1&obfs=salamander&obfs-password=$OBFS_ENC&sni=$SNI"
URI_HOPPING="hysteria2://$AUTH_ENC@$SERVER_ADDR:3000-19999?insecure=1&obfs=salamander&obfs-password=$OBFS_ENC&sni=$SNI"

# ================ SUMMARY ================
echo ""
echo "====================================================="
echo "     HYSTERIA 2 INSTALLATION COMPLETE"
echo "====================================================="
echo ""
echo "Server Address   : $SERVER_ADDR"
echo "Standard Port    : $HY_PORT/udp"
echo "Hopping Range    : 3000-19999/udp"
echo "Auth Password    : $AUTH_PASS"
echo "Obfs Password    : $OBFS_PASS"
echo "SNI              : $SNI"
echo "Bandwidth        : $BANDWIDTH Mbps"
echo ""
echo "--- CLIENT URI (STANDARD) ---"
echo "$URI"
echo ""
echo "--- CLIENT URI (PORT HOPPING - RECOMMENDED) ---"
echo "$URI_HOPPING"
echo ""
echo "--- USEFUL COMMANDS ---"
echo "Check service   : systemctl status hysteria-server"
echo "View logs       : journalctl -u hysteria-server -f -n 50"
echo "Check UFW rules : ufw status numbered"
echo "Check DNAT rule : iptables -t nat -L PREROUTING -v | grep 3000:19999"
echo ""
echo "Port hopping: Client dapat menggunakan port acak dari 3000-19999"
echo "Semua UDP ke range tersebut akan diteruskan ke port $HY_PORT"
echo "====================================================="

exit 0
