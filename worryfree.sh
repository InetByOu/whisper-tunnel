#!/bin/bash
# =============================================================================
# worryfree.sh - Hysteria 2 Full One-Click Installer + Auto Update
# Auth password OPSIONAL - default gstgg47e jika Enter kosong
# Support: Ubuntu/Debian - Jalankan sebagai root
# Fitur: apt auto update, deps full, port hopping 3000-19999, obfs salamander,
#        self-signed cert, URI client siap pakai
# =============================================================================

set -e

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\( {GREEN}=== worryfree.sh - Instalasi Hysteria 2 dimulai === \){NC}"
echo -e "\( {YELLOW}Versi terbaru - Dibuat khusus untuk kemudahan tanpa worry \){NC}"

# 0. Cek OS (hanya Debian/Ubuntu)
if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
    echo -e "\( {RED}Script ini hanya support Debian/Ubuntu-based. Keluar. \){NC}"
    exit 1
fi

# 1. Auto update & upgrade sistem + install dependencies otomatis
echo -e "\( {YELLOW}Auto update & upgrade paket sistem... \){NC}"
apt update -y && apt upgrade -y && apt autoremove -y

echo -e "\( {YELLOW}Install dependencies otomatis... \){NC}"
apt install -y curl wget openssl iptables ufw jq net-tools iptables-persistent netfilter-persistent ca-certificates

# 2. Install Hysteria 2 via script resmi (upgrade jika sudah ada)
echo -e "\( {YELLOW}Install/Upgrade Hysteria 2 official... \){NC}"
bash <(curl -fsSL https://get.hy2.sh/)

# Pastikan binary ada
if ! command -v hysteria &> /dev/null; then
    echo -e "\( {RED}Gagal install Hysteria. Cek koneksi/internet. \){NC}"
    exit 1
fi

# 3. Prompt konfigurasi (auth password opsional dengan default)
echo -e "\( {YELLOW}Masukkan konfigurasi (tekan Enter untuk default): \){NC}"

read -p "Port listen Hysteria (default: 5667): " HY_PORT
HY_PORT=${HY_PORT:-5667}

# Auth password: opsional, default gstgg47e jika kosong
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

# 4. Generate self-signed cert (CN = SNI, valid 10 tahun)
CERT_DIR="/etc/hysteria"
mkdir -p $CERT_DIR
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout $CERT_DIR/server.key \
    -out $CERT_DIR/server.crt \
    -subj "/CN=$SNI" 2>/dev/null

chmod 600 $CERT_DIR/server.key
echo -e "${GREEN}Self-signed cert dibuat (CN: \( SNI). \){NC}"

# 5. Buat config.yaml lengkap
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

echo -e "${GREEN}Config dibuat di: \( CONFIG_FILE \){NC}"

# 6. Restart & enable service
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

# 7. Setup iptables DNAT permanen untuk port hopping (3000-19999 -> HY_PORT)
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    echo -e "\( {YELLOW}Interface default tidak terdeteksi. Setup iptables manual nanti. \){NC}"
else
    echo -e "${YELLOW}Setup iptables DNAT (range 3000-19999 -> $HY_PORT via \( INTERFACE) \){NC}"
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 3000:19999 -j DNAT --to-destination :$HY_PORT
    iptables -t nat -A POSTROUTING -p udp -j MASQUERADE

    # Simpan permanen
    netfilter-persistent save
    echo -e "\( {GREEN}Iptables disimpan permanen. \){NC}"
fi

# 8. Buka port di ufw jika aktif
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow $HY_PORT/udp
    ufw allow 3000:19999/udp
    ufw reload
    echo -e "${GREEN}UFW: Port \( HY_PORT + range 3000-19999/udp dibuka. \){NC}"
else
    echo -e "\( {YELLOW}UFW tidak aktif. Buka port manual via firewall VPS/provider. \){NC}"
fi

# 9. Buat URI client siap pakai
SERVER_IP=$(curl -s ifconfig.me || echo "your-server-ip")
URI="hysteria2://\( {AUTH_PASS}@ \){SERVER_IP}:\( {HY_PORT}/?obfs=salamander&obfs-password= \){OBFS_PASS}&sni=${SNI}&insecure=1"

read -p "Domain kamu (kosongkan jika pakai IP saja): " DOMAIN
if [ ! -z "$DOMAIN" ]; then
    URI="hysteria2://\( {AUTH_PASS}@ \){DOMAIN}:\( {HY_PORT}/?obfs=salamander&obfs-password= \){OBFS_PASS}&sni=${SNI}&insecure=1"
fi

echo ""
echo -e "\( {GREEN}=== Instalasi worryfree.sh Selesai! === \){NC}"
echo -e "Server IP/Domain     : ${DOMAIN:-$SERVER_IP}"
echo -e "Port internal        : $HY_PORT"
echo -e "Range hopping client : 3000-19999"
echo -e "Auth password        : $AUTH_PASS"
echo -e "Obfs password        : $OBFS_PASS"
echo -e "SNI                  : $SNI"
echo ""
echo -e "\( {YELLOW}URI client (copy ke Hiddify/NekoBox/Android): \){NC}"
echo "$URI"
echo ""
echo -e "\( {YELLOW}Untuk full hopping: Ganti port di URI jadi :3000-19999 \){NC}"
echo -e "Cek status/log   : systemctl status hysteria-server   atau   journalctl -u hysteria-server -e -f"
echo -e "Update Hysteria  : bash <(curl -fsSL https://get.hy2.sh/)"
echo ""
echo -e "\( {GREEN}Semua sudah worryfree sekarang! Selamat menikmati koneksi cepat & aman dari Bandung. \){NC}"
