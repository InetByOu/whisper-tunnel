#!/usr/bin/env python3
"""
UDTUN Server Configuration
"""

import json
import os
import socket
from dataclasses import dataclass, field
from typing import Tuple

@dataclass
class ServerConfig:
    """Server configuration"""
    
    # Network settings
    udp_port_range: Tuple[int, int] = (6000, 19999)
    listen_port: int = 5667
    bind_ip: str = "0.0.0.0"
    
    # TUN settings
    tun_name: str = "udtun0"
    tun_ip: str = "10.9.0.1"
    tun_netmask: str = "255.255.255.0"
    tun_mtu: int = 1300
    
    # Session settings
    session_timeout: int = 30
    keepalive_interval: int = 10
    max_clients: int = 1000
    
    # Performance
    udp_buffer_size: int = 4194304  # 4MB
    max_packet_size: int = 1500
    read_timeout: float = 0.01
    
    # Security
    enable_rate_limit: bool = True
    rate_limit_per_client: int = 1000  # packets per second
    
    # Logging
    log_file: str = "/var/log/udtun/server.log"
    log_level: str = "INFO"  # DEBUG, INFO, WARNING, ERROR
    
    def __post_init__(self):
        """Post initialization"""
        # Ensure directories exist
        os.makedirs(os.path.dirname(self.log_file), exist_ok=True)

def get_server_ip() -> str:
    """Get server's public IP address"""
    try:
        # Try to get public IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "0.0.0.0"

def load_config(config_path: str = "/etc/udtun/server.json") -> ServerConfig:
    """Load configuration from file"""
    config = ServerConfig()
    
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r') as f:
                data = json.load(f)
                
                # Convert port range from list to tuple if needed
                if 'udp_port_range' in data and isinstance(data['udp_port_range'], list):
                    data['udp_port_range'] = tuple(data['udp_port_range'])
                
                for key, value in data.items():
                    if hasattr(config, key):
                        setattr(config, key, value)
                        
            print(f"Configuration loaded from {config_path}")
        except Exception as e:
            print(f"Warning: Could not load config: {e}")
    else:
        print(f"Config file {config_path} not found, using defaults")
    
    return config

def save_config(config: ServerConfig, config_path: str = "/etc/udtun/server.json"):
    """Save configuration to file"""
    try:
        os.makedirs(os.path.dirname(config_path), exist_ok=True)
        
        config_dict = {}
        for key in config.__dataclass_fields__:
            value = getattr(config, key)
            config_dict[key] = value
        
        with open(config_path, 'w') as f:
            json.dump(config_dict, f, indent=4)
            
        print(f"Configuration saved to {config_path}")
    except Exception as e:
        print(f"Error saving config: {e}")
