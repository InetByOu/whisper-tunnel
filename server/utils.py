#!/usr/bin/env python3
"""
Utility functions
"""

import os
import sys
import time
import struct
import socket
import select
import logging
from typing import Optional, Tuple, List
from ipaddress import ip_address, IPv4Address

def setup_logging(log_file: str, log_level: str = "INFO") -> logging.Logger:
    """Setup logging configuration"""
    logger = logging.getLogger("udtun")
    logger.setLevel(getattr(logging, log_level.upper()))
    
    # File handler
    fh = logging.FileHandler(log_file)
    fh.setLevel(getattr(logging, log_level.upper()))
    
    # Console handler
    ch = logging.StreamHandler()
    ch.setLevel(getattr(logging, log_level.upper()))
    
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    fh.setFormatter(formatter)
    ch.setFormatter(formatter)
    
    logger.addHandler(fh)
    logger.addHandler(ch)
    
    return logger

def get_local_ip() -> str:
    """Get local IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def is_valid_ipv4(packet: bytes) -> bool:
    """Check if packet is valid IPv4"""
    if len(packet) < 20:
        return False
    
    version = packet[0] >> 4
    ihl = packet[0] & 0x0F
    
    if version != 4:
        return False
    
    if ihl < 5:
        return False
    
    total_length = struct.unpack('!H', packet[2:4])[0]
    if total_length < 20 or total_length > 65535:
        return False
    
    if len(packet) < total_length:
        return False
    
    # Verify checksum
    header = packet[:ihl*4]
    if ipv4_checksum(header) != 0:
        return False
    
    return True

def ipv4_checksum(header: bytes) -> int:
    """Calculate IPv4 checksum"""
    if len(header) % 2 == 1:
        header += b'\x00'
    
    s = 0
    for i in range(0, len(header), 2):
        w = header[i] + (header[i+1] << 8)
        s = (s + w) & 0xFFFF
        s = (s + (s >> 16)) & 0xFFFF
    
    return ~s & 0xFFFF

def create_packet_id() -> int:
    """Create packet ID based on timestamp"""
    return int(time.time() * 1000) & 0xFFFFFFFF

def non_blocking_read(fd, size: int) -> bytes:
    """Non-blocking read"""
    try:
        ready, _, _ = select.select([fd], [], [], 0.001)
        if ready:
            return os.read(fd, size)
    except (BlockingIOError, InterruptedError):
        pass
    except OSError:
        pass
    return b""
