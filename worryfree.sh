#!/bin/bash
# worryfree.sh - One-click Hysteria 2 installer for Ubuntu 24.04 with port hopping
# Menggunakan UFW + iptables DNAT untuk port hopping
# No colors, plain text output

set -e

# ==================== ROOT CHECK ====================
echo "[1/16] Checking root privileges..."
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root. Use sudo -i or su root."
    exit 1
fi
echo "OK: Running as root."

# ==================== CLEANUP ====================
echo "[2/16] Cleaning up existing Hysteria 2 installation..."

# Stop and disable service
if systemctl list-unit-files 2>/dev/null | grep -q hysteria-server; then
    echo "Stopping and disabling hysteria-server service..."
    systemctl stop hysteria-server 2>/dev/null || true
    systemctl disable hysteria-server 2>/dev/null || true
fi

# Remove config files and certificates
rm -f /etc/hysteria/config.yaml /etc/hysteria/*.crt /etc/hysteria/*.key 2>/dev/null || true

# Remove binary
rm -f /usr/local/bin/hysteria 2>/dev/null || true

# Remove systemd service file
rm -f /etc/systemd/system/hysteria-server.service 2>/dev/null || true

# Cleanup iptables rules
echo "Cleaning up old iptables rules..."

# Detect interface
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
fi
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi

# Remove existing DNAT rules
iptables -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true

# Reset UFW sepenuhnya
echo "Resetting UFW..."
ufw --force disable 2>/dev/null || true
ufw --force reset 2>/dev/null || true

echo "Cleanup completed."

# ==================== SYSTEM UPDATE ====================
echo "[3/16] Updating system packages..."
apt update -y
apt upgrade -y
apt autoremove -y
echo "System update completed."

# ==================== DEPENDENCIES ====================
echo "[4/16] Installing dependencies..."
apt install -y curl wget openssl jq net-tools ca-certificates ufw iptables
echo "Dependencies installed."

# ==================== INSTALL HYSTERIA 2 ====================
echo "[5/16] Installing Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/) || { echo "Error: Hysteria installation failed."; exit 1; }
echo "Hysteria 2 installed successfully."

# ==================== PROMPT CONFIGURATION ====================
echo "[6/16] Configuring Hysteria 2..."

# Default values
DEFAULT_HY_PORT="5667"
DEFAULT_AUTH_PASS="gstgg47e"
DEFAULT_OBFS_PASS="huhqb\`c"
DEFAULT_SNI="graph.facebook.com"
DEFAULT_BANDWIDTH="100"

# Read user input
read -p "Enter Hysteria listen port [$DEFAULT_HY_PORT]: " HY_PORT
HY_PORT=${HY_PORT:-$DEFAULT_HY_PORT}

read -p "Enter authentication password [$DEFAULT_AUTH_PASS]: " AUTH_PASS
AUTH_PASS=${AUTH_PASS:-$DEFAULT_AUTH_PASS}

read -p "Enter obfuscation password (salamander) [$DEFAULT_OBFS_PASS]: " OBFS_PASS
OBFS_PASS=${OBFS_PASS:-$DEFAULT_OBFS_PASS}

read -p "Enter SNI/server_name [$DEFAULT_SNI]: " SNI
SNI=${SNI:-$DEFAULT_SNI}

read -p "Enter bandwidth up/down in Mbps [$DEFAULT_BANDWIDTH]: " BANDWIDTH
BANDWIDTH=${BANDWIDTH:-$DEFAULT_BANDWIDTH}

echo "Configuration values set."

# ==================== GENERATE CERTIFICATE ====================
echo "[7/16] Generating self-signed certificate (10 years validity)..."
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -days 3650 \
    -subj "/CN=$SNI" 2>/dev/null
echo "Certificate generated at /etc/hysteria/server.crt and /etc/hysteria/server.key"

# ==================== CREATE CONFIG.YAML ====================
echo "[8/16] Creating Hysteria 2 configuration file..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :$HY_PORT

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
    password: $OBFS_PASS

masquerade:
  type: proxy
  proxy:
    url: https://www.google.com/
    rewriteHost: true

log:
  level: info
EOF
echo "Configuration file created at /etc/hysteria/config.yaml"

# ==================== DETECT INTERFACE ====================
echo "[9/16] Detecting main network interface..."
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
fi
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
    echo "Warning: Could not detect default interface, using $INTERFACE"
else
    echo "Detected main interface: $INTERFACE"
fi

# ==================== CONFIGURE UFW ====================
echo "[10/16] Configuring UFW firewall..."

# Pastikan UFW dalam keadaan reset
ufw --force disable
ufw --force reset

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (port 22) - gunakan sintaks panjang
ufw allow proto tcp to any port 22 comment 'SSH'

# Allow Hysteria main port
ufw allow proto udp to any port $HY_PORT comment 'Hysteria main port'

# Allow port hopping range 3000-19999 - gunakan sintaks panjang
ufw allow proto udp to any port 3000:19999 comment 'Hysteria port hopping'

# Enable UFW
ufw --force enable

# Tampilkan status
ufw status verbose

echo "UFW configured successfully."

# ==================== CONFIGURE IPTABLES DNAT ====================
echo "[11/16] Configuring iptables DNAT for port hopping..."

# Hapus rule lama jika ada
iptables -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :$HY_PORT 2>/dev/null || true

# Tambah rule DNAT
iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 3000:19999 -j DNAT --to-destination :$HY_PORT

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo "iptables DNAT rule added: UDP 3000-19999 -> :$HY_PORT"

# ==================== ENABLE HYSTERIA SERVICE ====================
echo "[12/16] Enabling and starting Hysteria service..."
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server
echo "Hysteria service enabled and restarted."

# ==================== CHECK SERVICE STATUS ====================
echo "[13/16] Checking Hysteria service status..."
if systemctl is-active --quiet hysteria-server; then
    echo "Hysteria service is active and running."
else
    echo "Error: Hysteria service failed to start. Check with: systemctl status hysteria-server"
    exit 1
fi

# ==================== GENERATE CLIENT URI ====================
echo "[14/16] Generating client connection URI..."

# Get public IP
PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me || true)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --connect-timeout 5 icanhazip.com || true)
fi
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --connect-timeout 5 ipinfo.io/ip || true)
fi
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
fi
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="YOUR_SERVER_IP"
    echo "Warning: Could not detect public IP. Please replace YOUR_SERVER_IP manually."
fi

# Prompt for domain
read -p "Enter domain name (optional, press Enter to use IP $PUBLIC_IP): " DOMAIN
SERVER_ADDR=${DOMAIN:-$PUBLIC_IP}

# URL encode password menggunakan jq (jika tersedia)
if command -v jq >/dev/null 2>&1; then
    OBFS_PASS_ENCODED=$(printf "%s" "$OBFS_PASS" | jq -sRr @uri)
    AUTH_PASS_ENCODED=$(printf "%s" "$AUTH_PASS" | jq -sRr @uri)
else
    # Fallback sederhana
    OBFS_PASS_ENCODED=$(echo -n "$OBFS_PASS" | od -An -tx1 | tr ' ' % | tr -d '\n' | tr '[:upper:]' '[:lower:]')
    AUTH_PASS_ENCODED=$(echo -n "$AUTH_PASS" | od -An -tx1 | tr ' ' % | tr -d '\n' | tr '[:upper:]' '[:lower:]')
fi

# Generate URIs
URI="hysteria2://$AUTH_PASS_ENCODED@$SERVER_ADDR:$HY_PORT?insecure=1&obfs=salamander&obfs-password=$OBFS_PASS_ENCODED&sni=$SNI"
URI_HOPPING="hysteria2://$AUTH_PASS_ENCODED@$SERVER_ADDR:3000-19999?insecure=1&obfs=salamander&obfs-password=$OBFS_PASS_ENCODED&sni=$SNI"

echo "Client URI generated."

# ==================== PERSISTENT IPTABLES ====================
echo "[15/16] Making iptables rules persistent..."

# Install iptables-persistent tanpa prompt
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent

# Save iptables rules
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "iptables rules saved."

# ==================== SUMMARY ====================
echo "[16/16] Installation Summary"
echo "================================================"
echo "Hysteria 2 has been successfully installed!"
echo "================================================"
echo ""
echo "Server Information:"
echo "  Address: $SERVER_ADDR"
echo "  Port (standard): $HY_PORT"
echo "  Port hopping range: 3000-19999"
echo "  Authentication password: $AUTH_PASS"
echo "  Obfuscation type: salamander"
echo "  Obfuscation password: $OBFS_PASS"
echo "  SNI: $SNI"
echo "  Bandwidth: $BANDWIDTH Mbps"
echo ""
echo "Firewall Status:"
echo "  UFW: active"
echo "  UFW rules:"
ufw status | grep -E "$HY_PORT|3000:19999|22" | sed 's/^/    /'
echo ""
echo "Port Hopping DNAT Rule:"
echo "  iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 3000:19999 -j DNAT --to-destination :$HY_PORT"
echo ""
echo "Client Connection URIs:"
echo "  Standard port:"
echo "  $URI"
echo ""
echo "  Port hopping (recommended - use any port from 3000-19999):"
echo "  $URI_HOPPING"
echo ""
echo "Useful Commands:"
echo "  Check Hysteria status: systemctl status hysteria-server"
echo "  View Hysteria logs: journalctl -u hysteria-server -f -n 50"
echo "  Check UFW status: ufw status"
echo "  Check DNAT rules: iptables -t nat -L PREROUTING -v"
echo "  Edit config: nano /etc/hysteria/config.yaml"
echo "  Restart Hysteria: systemctl restart hysteria-server"
echo ""
echo "================================================"

# ==================== TEST CONNECTION ====================
echo ""
echo "Quick test: Checking if Hysteria port is listening..."
if command -v ss >/dev/null 2>&1; then
    if ss -uln | grep -q ":$HY_PORT "; then
        echo "✓ Port $HY_PORT is listening (UDP)"
    else
        echo "✗ Port $HY_PORT is NOT listening. Check Hysteria service."
    fi
fi

echo ""
echo "Installation complete! Use the URI above to connect your clients."
echo "================================================"

exit 0
