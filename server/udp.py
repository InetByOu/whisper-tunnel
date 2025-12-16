#!/usr/bin/env python3
"""
UDP Packet Handler - WHISPER Tunnel Server
"""

import socket
import struct
import time
from typing import Optional, Tuple, List, Dict
from .utils import validate_packet, get_time_ms

class UDPPacket:
    """UDP packet encoder/decoder"""
    
    # Packet types
    TYPE_DATA = 0x01
    TYPE_KEEPALIVE = 0x02
    TYPE_PROBE = 0x03
    
    @staticmethod
    def encode_data(session_id: str, seq_num: int, payload: bytes) -> bytes:
        """Encode data packet"""
        # Format: TYPE(1) | SESSION_ID(16) | SEQ(4) | PAYLOAD
        session_bytes = session_id.encode()[:16].ljust(16, b'\x00')
        header = struct.pack("!B16sI", UDPPacket.TYPE_DATA, session_bytes, seq_num)
        return header + payload
    
    @staticmethod
    def encode_keepalive(session_id: str) -> bytes:
        """Encode keepalive packet"""
        session_bytes = session_id.encode()[:16].ljust(16, b'\x00')
        return struct.pack("!B16s", UDPPacket.TYPE_KEEPALIVE, session_bytes)
    
    @staticmethod
    def encode_probe() -> bytes:
        """Encode probe packet"""
        return struct.pack("!B", UDPPacket.TYPE_PROBE)
    
    @staticmethod
    def decode(packet: bytes) -> Optional[Tuple[int, str, int, bytes]]:
        """Decode UDP packet"""
        if not validate_packet(packet, min_size=17):
            return None
        
        try:
            ptype = packet[0]
            
            if ptype == UDPPacket.TYPE_DATA:
                # Data packet
                session_id = packet[1:17].rstrip(b'\x00').decode()
                seq_num = struct.unpack("!I", packet[17:21])[0]
                payload = packet[21:]
                return (ptype, session_id, seq_num, payload)
            
            elif ptype == UDPPacket.TYPE_KEEPALIVE:
                # Keepalive packet
                session_id = packet[1:17].rstrip(b'\x00').decode()
                return (ptype, session_id, 0, b'')
            
            elif ptype == UDPPacket.TYPE_PROBE:
                # Probe packet
                return (ptype, "", 0, b'')
            
        except Exception:
            pass
        
        return None

class UDPHandler:
    """UDP socket handler"""
    
    def __init__(self, port: int, bind_addr: str = "0.0.0.0"):
        self.port = port
        self.socket = None
        self.bind_addr = bind_addr
    
    def start(self) -> bool:
        """Start UDP listener"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            # Enable port reuse if available
            try:
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            except AttributeError:
                pass
            
            # Set non-blocking
            self.socket.setblocking(False)
            
            # Set buffer sizes
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2097152)
            
            # Bind socket
            self.socket.bind((self.bind_addr, self.port))
            
            print(f"UDP listener started on {self.bind_addr}:{self.port}")
            return True
            
        except Exception as e:
            print(f"Failed to start UDP listener: {e}")
            return False
    
    def receive(self, max_packets: int = 32) -> List[Tuple[bytes, Tuple[str, int]]]:
        """Receive UDP packets"""
        packets = []
        
        if not self.socket:
            return packets
        
        try:
            for _ in range(max_packets):
                try:
                    data, addr = self.socket.recvfrom(65536)
                    if data:
                        packets.append((data, addr))
                except BlockingIOError:
                    break
                except socket.error:
                    break
        except Exception as e:
            print(f"Error receiving UDP: {e}")
        
        return packets
    
    def send(self, data: bytes, addr: Tuple[str, int]) -> bool:
        """Send UDP packet"""
        if not self.socket:
            return False
        
        try:
            self.socket.sendto(data, addr)
            return True
        except Exception as e:
            print(f"Error sending UDP: {e}")
            return False
    
    def close(self):
        """Close UDP socket"""
        if self.socket:
            self.socket.close()
            self.socket = None
