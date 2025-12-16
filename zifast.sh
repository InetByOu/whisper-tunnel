#!/bin/bash
# Zivpn UDP Module installer - Optimized Version
# Creator Zahid Islam

# Enable exit on error and logging
set -e
exec 2> >(tee -a /var/log/zivpn-install.log)

echo "Updating server with fastest mirrors..."
{
    # Use fastest mirrors and parallel downloads
    sudo sed -i 's/^#\(deb.*partner\)/\1/' /etc/apt/sources.list
    sudo apt-get update -o Acquire::ForceIPv4=true -o Acquire::http::No-Cache=true -o Acquire::http::Pipeline-Depth="10" -o Acquire::https::No-Cache=true
    DEBIAN_FRONTEND=noninteractive sudo apt-get upgrade -y --allow-change-held-packages --fix-missing
    sudo apt-get install -y curl wget net-tools jq iptables-persistent netfilter-persistent
} > /dev/null 2>&1

echo "Stopping existing service..."
{
    systemctl stop zivpn.service 2>/dev/null || true
    systemctl disable zivpn.service 2>/dev/null || true
    pkill -f "zivpn server" 2>/dev/null || true
} > /dev/null 2>&1

echo "Downloading UDP Service with optimization..."
{
    # Download with retry and faster options
    for i in {1..3}; do
        if wget -q --show-progress --timeout=30 --tries=3 --retry-connrefused \
           https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
           -O /usr/local/bin/zivpn; then
            break
        fi
        sleep 2
    done
    
    chmod +x /usr/local/bin/zivpn
    mkdir -p /etc/zivpn
    
    # Download config with retry
    for i in {1..3}; do
        if curl -sSL --connect-timeout 20 --retry 3 \
           https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json \
           -o /etc/zivpn/config.json; then
            break
        fi
        sleep 2
    done
} > /dev/null 2>&1

echo "Generating optimized certificates..."
{
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2>/dev/null
} > /dev/null 2>&1

echo "Applying kernel optimizations for maximum speed..."
{
    # UDP buffer optimizations
    cat >> /etc/sysctl.conf << 'EOF'
# ZIVPN UDP Optimizations
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.optmem_max=67108864
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.udp_mem=786432 1048576 16777216
net.core.netdev_max_backlog=100000
net.core.somaxconn=65535
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
fs.file-max=2097152
net.ipv4.ip_local_port_range=1024 65535
EOF
    
    # Apply immediately
    sysctl -p > /dev/null 2>&1
    
    # Increase system limits
    echo "* soft nofile 1048576" >> /etc/security/limits.conf
    echo "* hard nofile 1048576" >> /etc/security/limits.conf
    echo "root soft nofile 1048576" >> /etc/security/limits.conf
    echo "root hard nofile 1048576" >> /etc/security/limits.conf
} > /dev/null 2>&1

echo "Creating optimized service configuration..."
cat > /etc/systemd/system/zivpn.service << 'EOF'
[Unit]
Description=zivpn VPN Server - Optimized
After=network.target network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=1
StartLimitBurst=0
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
StandardOutput=null
StandardError=journal
SyslogIdentifier=zivpn
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=5
Environment=ZIVPN_LOG_LEVEL=error
Environment=GODEBUG=netdns=go
Environment=GOMAXPROCS=auto
Nice=-10
IOSchedulingClass=realtime
IOSchedulingPriority=0
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
CPUAffinity=0-3
OOMScoreAdjust=-1000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_ADMIN CAP_SYS_NICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_ADMIN CAP_SYS_NICE
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

# Create optimized config with user input
echo "ZIVPN UDP Passwords"
read -p "Enter passwords separated by commas, example: pass1,pass2 (Press enter for Default 'zi'): " input_config

if [ -n "$input_config" ]; then
    IFS=',' read -r -a config <<< "$input_config"
    if [ ${#config[@]} -eq 1 ]; then
        config+=("${config[0]}")
    fi
else
    config=("zi")
fi

# Create optimized config file
cat > /etc/zivpn/config.json << EOF
{
  "server": "0.0.0.0:5667",
  "key": "/etc/zivpn/zivpn.key",
  "cert": "/etc/zivpn/zivpn.crt",
  "timeout": 300,
  "udp_timeout": 60,
  "max_packets": 10000,
  "log_level": "error",
  "disable_log_timestamp": true,
  "gc_interval": 300,
  "config": [
$(printf '    "%s",\n' "${config[@]}" | sed '$s/,$//')
  ],
  "advanced": {
    "udp_buffer_size": 4194304,
    "max_udp_packet_size": 65507,
    "worker_processes": 4,
    "read_buffer": 65536,
    "write_buffer": 65536,
    "tcp_fast_open": true,
    "reuse_port": true,
    "tcp_keepalive": 300
  }
}
EOF

echo "Configuring firewall and port forwarding..."
{
    # Get main interface
    INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    # Clear existing rules
    iptables -t nat -F PREROUTING 2>/dev/null || true
    
    # Add optimized port forwarding
    iptables -t nat -A PREROUTING -i $INTERFACE -p udp -m udp --dport 6000:19999 -j DNAT --to-destination :5667
    iptables -t nat -A PREROUTING -i $INTERFACE -p tcp -m tcp --dport 6000:19999 -j DNAT --to-destination :5667
    
    # Allow all ports
    ufw --force enable > /dev/null 2>&1 || true
    ufw default allow incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow 5667 > /dev/null 2>&1
    ufw allow 6000:19999/tcp > /dev/null 2>&1
    ufw allow 6000:19999/udp > /dev/null 2>&1
    
    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
} > /dev/null 2>&1

echo "Starting optimized service..."
{
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    
    # Wait and check status
    sleep 2
    if systemctl is-active --quiet zivpn.service; then
        echo "✓ Service started successfully"
        
        # Display connection info
        IP=$(curl -s4 ifconfig.co || curl -s4 icanhazip.com || echo "IP_NOT_FOUND")
        echo "========================================="
        echo "ZIVPN UDP Server Installation Complete!"
        echo "Server IP: $IP"
        echo "Port Range: 6000-19999 (TCP/UDP)"
        echo "Main Port: 5667"
        echo "Passwords: ${config[*]}"
        echo "========================================="
        
        # Show service status
        echo -e "\nService Status:"
        systemctl status zivpn.service --no-pager -l
    else
        echo "✗ Service failed to start"
        journalctl -u zivpn.service -n 20 --no-pager
    fi
} > /dev/null 2>&1

# Cleanup
rm -f zi.* 2>/dev/null || true

echo -e "\nOptimization complete! Server is configured for maximum UDP throughput."
