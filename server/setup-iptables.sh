#!/bin/bash

# ============================================
# SETUP IPTABLES FOR UDP TUNNEL SERVER
# ============================================

set -e  # Exit on error

echo "[+] Setting up iptables for UDP Tunnel Server..."

# Install iptables-persistent jika belum ada
if ! dpkg -l | grep -q iptables-persistent; then
    echo "[+] Installing iptables-persistent..."
    apt-get update
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y iptables-persistent
fi

# Buat direktori jika tidak ada
mkdir -p /etc/iptables

# Flush existing rules
echo "[+] Flushing existing iptables rules..."
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# Default policies (lebih aman)
echo "[+] Setting default policies..."
iptables -P INPUT ACCEPT  # Untuk testing, bisa diganti DROP setelah setup
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow UDP tunnel port (contoh: 5555)
TUNNEL_PORT=5555
echo "[+] Allowing UDP port $TUNNEL_PORT..."
iptables -A INPUT -p udp --dport $TUNNEL_PORT -j ACCEPT

# Allow management SSH (default port 22)
SSH_PORT=22
echo "[+] Allowing SSH port $SSH_PORT..."
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

# Allow ICMP (ping)
echo "[+] Allowing ICMP (ping)..."
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# NAT for tunnel traffic (sesuaikan dengan network tunnel Anda)
TUNNEL_NETWORK="10.8.0.0/24"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "[+] Setting up NAT for network $TUNNEL_NETWORK on interface $INTERFACE..."
iptables -t nat -A POSTROUTING -s $TUNNEL_NETWORK -o $INTERFACE -j MASQUERADE

# Forwarding rules for tunnel
echo "[+] Setting up forwarding rules..."
iptables -A FORWARD -s $TUNNEL_NETWORK -j ACCEPT
iptables -A FORWARD -d $TUNNEL_NETWORK -j ACCEPT

# Drop invalid packets
echo "[+] Adding rule to drop invalid packets..."
iptables -A INPUT -m state --state INVALID -j DROP
iptables -A FORWARD -m state --state INVALID -j DROP

# Rate limiting untuk mencegah abuse (opsional)
echo "[+] Adding rate limiting..."
iptables -A INPUT -p udp --dport $TUNNEL_PORT -m state --state NEW -m recent --set
iptables -A INPUT -p udp --dport $TUNNEL_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 20 -j DROP

# Tampilkan rules yang dibuat
echo "[+] Current iptables rules:"
echo "=========================================="
iptables -L -n -v
echo "=========================================="
iptables -t nat -L -n -v
echo "=========================================="

# Simpan rules
echo "[+] Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4

# Untuk IPv6 (jika tidak digunakan, bisa disable)
ip6tables-save > /etc/iptables/rules.v6

# Enable iptables-persistent
echo "[+] Enabling iptables-persistent service..."
systemctl enable netfilter-persistent 2>/dev/null || true

# Reload service
echo "[+] Reloading iptables-persistent..."
systemctl restart netfilter-persistent 2>/dev/null || \
service netfilter-persistent restart 2>/dev/null || \
/etc/init.d/netfilter-persistent restart 2>/dev/null || true

echo "[+] Setup completed!"
echo "[+] Rules saved to /etc/iptables/rules.v4"
