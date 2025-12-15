#!/bin/bash

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow UDP tunnel port (example: 5555)
iptables -A INPUT -p udp --dport 5555 -j ACCEPT

# Allow management SSH (adjust port as needed)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# NAT for tunnel traffic
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

# Forwarding rules
iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
iptables -A FORWARD -d 10.8.0.0/24 -j ACCEPT

# Drop invalid packets early
iptables -A INPUT -m state --state INVALID -j DROP
iptables -A FORWARD -m state --state INVALID -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4
