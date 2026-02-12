#!/bin/bash
# =============================================================================
# worryfree.sh - Hysteria 2 Installer Compatible Ubuntu 24.04 (nftables)
# Auth password OPSIONAL - default gstgg47e jika Enter kosong
# Support: Ubuntu 24.04 LTS (Noble) - Jalankan sebagai root
# Fitur: apt auto update, nftables persistent, port hopping 3000-19999 DNAT,
#        obfs salamander, self-signed cert, URI client siap pakai
# =============================================================================

set -e

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\( {GREEN}=== worryfree.sh - Instalasi Hysteria 2 dimulai (Ubuntu 24.04 compatible) === \){NC}"
echo -e "\( {YELLOW}Menggunakan nftables untuk firewall & persistent rules (no ufw conflict) \){NC}"

# 0. Cek OS (Ubuntu/Debian, khusus 24.04+ recommended)
if ! grep -qiE 'ubuntu|debian' /etc/os-release; then
    echo -e "\( {RED}Script ini utama untuk Ubuntu/Debian. Keluar. \){NC}"
    exit 1
fi

# 1. Auto update & upgrade sistem + install dependencies minimal
echo -e "\( {YELLOW}Auto update & upgrade paket sistem... \){NC}"
apt update -y && apt upgrade -y && apt autoremove -y

echo -e "\( {YELLOW}Install dependencies otomatis (nftables + tools)... \){NC}"
apt install -y curl wget openssl nftables jq net-tools ca-certificates

# 2. Install Hysteria 2 via script resmi (upgrade jika sudah ada)
echo -e "\( {YELLOW}Install/Upgrade Hysteria 2 official... \){NC}"
bash <(curl -fsSL https://get.hy2.sh/)

if ! command -v hysteria &> /dev/null; then
    echo -e "\( {RED}Gagal install Hysteria. Cek koneksi. \){NC}"
    exit 1
fi

# 3. Prompt konfigurasi
echo -e "\( {YELLOW}Masukkan konfigurasi (tekan Enter untuk default): \){NC}"

read -p "Port listen Hysteria (default: 5667): " HY_PORT
HY_PORT=${HY_PORT:-5667}

read -p "Password auth (default: gstgg47e, tekan Enter untuk default): " AUTH_PASS
if [ -z "$AUTH_PASS" ]; then
    AUTH_PASS="gstgg47e"
    echo -e "\( {YELLOW}Menggunakan default auth password: gstgg47e \){NC}"
else
    echo -e "${YELLOW}Menggunakan auth password custom: \( AUTH_PASS \){NC}"
fi

read -p "Obfs salamander password (default: hu\`\`hqb\`c): " OBFS_PASS
OBFS_PASS=${OBFS_PASS:-hu``hqb`c}

read -p "SNI / server_name (default: graph.facebook.com): " SNI
SNI=${SNI:-graph.facebook.com}

read -p "Up / Down Mbps (default: 100): " MBPS
MBPS=${MBPS:-100}

# 4. Generate self-signed cert
CERT_DIR="/etc/hysteria"
mkdir -p $CERT_DIR
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout $CERT_DIR/server.key \
    -out $CERT_DIR/server.crt \
    -subj "/CN=$SNI" 2>/dev/null

chmod 600 $CERT_DIR/server.key
echo -e "${GREEN}Self-signed cert dibuat (CN: \( SNI). \){NC}"

# 5. Buat config Hysteria
CONFIG_FILE="/etc/hysteria/config.yaml"

cat > $CONFIG_FILE << EOF
listen: :$HY_PORT

tls:
  cert: $CERT_DIR/server.crt
  key: $CERT_DIR/server.key

auth:
  type: password
  password: $AUTH_PASS

bandwidth:
  up: ${MBPS} mbps
  down: ${MBPS} mbps

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

echo -e "${GREEN}Config Hysteria dibuat di: \( CONFIG_FILE \){NC}"

# 6. Setup nftables persistent rules
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"  # fallback umum
    echo -e "\( {YELLOW}Interface default tidak terdeteksi, pakai eth0 (ganti manual jika beda). \){NC}"
fi

NFT_CONF="/etc/nftables.conf"

cat > $NFT_CONF << EOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
        ct state established,related accept
        iif lo accept
        tcp dport 22 accept          # allow SSH (ganti jika port SSH beda)
        udp dport $HY_PORT accept    # Hysteria internal port
        udp dport 3000-19999 accept  # range hopping client
    }

    chain forward {
        type filter hook forward priority 0; policy accept;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport 3000-19999 dnat to :$HY_PORT
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "$INTERFACE" masquerade
    }
}
EOF

# Apply nftables config
nft -f $NFT_CONF

# Enable persistent load on boot
systemctl enable nftables
systemctl restart nftables

echo -e "${GREEN}nftables setup selesai: allow SSH + Hysteria port + range 3000-19999, DNAT hopping via \( INTERFACE. \){NC}"
echo -e "Cek rules: sudo nft list ruleset"

# 7. Restart & enable Hysteria service
systemctl daemon-reload
systemctl restart hysteria-server
systemctl enable hysteria-server --now

sleep 3
if systemctl is-active --quiet hysteria-server; then
    echo -e "\( {GREEN}Hysteria 2 service aktif! \){NC}"
else
    echo -e "\( {RED}Service gagal start. Cek: journalctl -u hysteria-server -xe \){NC}"
    exit 1
fi

# 8. Buat URI client
SERVER_IP=$(curl -s ifconfig.me || echo "your-server-ip")
URI="hysteria2://\( {AUTH_PASS}@ \){SERVER_IP}:\( {HY_PORT}/?obfs=salamander&obfs-password= \){OBFS_PASS}&sni=${SNI}&insecure=1"

read -p "Domain kamu (kosongkan jika pakai IP saja): " DOMAIN
if [ ! -z "$DOMAIN" ]; then
    URI="hysteria2://\( {AUTH_PASS}@ \){DOMAIN}:\( {HY_PORT}/?obfs=salamander&obfs-password= \){OBFS_PASS}&sni=${SNI}&insecure=1"
fi

echo ""
echo -e "\( {GREEN}=== Instalasi worryfree.sh Selesai! (nftables mode) === \){NC}"
echo -e "Server IP/Domain     : ${DOMAIN:-$SERVER_IP}"
echo -e "Port internal        : $HY_PORT"
echo -e "Range hopping client : 3000-19999 (DNAT otomatis)"
echo -e "Auth password        : $AUTH_PASS"
echo -e "Obfs password        : $OBFS_PASS"
echo -e "SNI                  : $SNI"
echo ""
echo -e "\( {YELLOW}URI client (copy ke Hiddify/NekoBox): \){NC}"
echo "$URI"
echo ""
echo -e "\( {YELLOW}Untuk full hopping: Ganti port di URI jadi :3000-19999 \){NC}"
echo -e "Cek nftables     : sudo nft list ruleset"
echo -e "Cek Hysteria log : journalctl -u hysteria-server -e -f"
echo -e "Update Hysteria  : bash <(curl -fsSL https://get.hy2.sh/)"
echo ""
echo -e "\( {GREEN}Semua worryfree di Ubuntu 24.04! Jika perlu allow port SSH lain atau IPv6, edit /etc/nftables.conf lalu sudo nft -f /etc/nftables.conf \){NC}"
