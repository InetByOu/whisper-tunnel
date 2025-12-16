#!/usr/bin/env python3
"""
Server Configuration
"""

import os
import sys
import json
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class ServerConfig:
    """Server configuration"""
    # UDP Settings
    udp_port_range: Tuple[int, int] = (6000, 19999)
    internal_port: int = 5667
    udp_bind_ip: str = "0.0.0.0"
    
    # TUN Settings
    tun_name: str = "udtun0"
    tun_ip: str = "10.9.0.1"
    tun_netmask: str = "255.255.255.0"
    tun_mtu: int = 1300
    
    # Session Settings
    session_timeout: int = 30  # seconds
    keepalive_interval: int = 10  # seconds
    max_sessions: int = 1000
    
    # Performance
    udp_buffer_size: int = 4194304  # 4MB
    batch_size: int = 32  # packets per batch
    max_packet_size: int = 1500
    
    # Security
    min_seq_window: int = 1024
    max_seq_window: int = 65536
    rate_limit_per_session: int = 100  # packets per second
    
    # Logging
    log_level: str = "INFO"
    log_file: str = "/var/log/udtun/server.log"

config = ServerConfig()

def load_config(config_path: str = None) -> ServerConfig:
    """Load configuration from file"""
    if config_path and os.path.exists(config_path):
        try:
            with open(config_path, 'r') as f:
                data = json.load(f)
                for key, value in data.items():
                    if hasattr(config, key):
                        setattr(config, key, value)
        except Exception as e:
            print(f"Warning: Could not load config: {e}")
    
    return config
