#!/usr/bin/env python3
"""
UDTUN Server Main Entry Point
"""

import sys
import time
import threading
from typing import Dict, Tuple

from .config import config, load_config
from .utils import setup_logging, get_local_ip
from .tun import TUNInterface
from .udp import UDPServer
from .session import SessionManager
from .ratelimit import AdaptiveRateLimiter
from .shutdown import ShutdownHandler

class UDTUNServer:
    """Main UDTUN server class"""
    
    def __init__(self):
        self.tun = TUNInterface()
        self.udp = UDPServer()
        self.sessions = SessionManager()
        self.rate_limiter = AdaptiveRateLimiter(max_rate=config.rate_limit_per_session)
        self.shutdown = ShutdownHandler()
        
        # Statistics
        self.stats = {
            'packets_in': 0,
            'packets_out': 0,
            'bytes_in': 0,
            'bytes_out': 0,
            'sessions': 0,
            'errors': 0
        }
        self.stats_lock = threading.Lock()
        
        # Setup logging
        self.logger = setup_logging(config.log_file, config.log_level)
        
        # Register shutdown callbacks
        self.shutdown.add_callback(self.cleanup)
    
    def start(self):
        """Start the server"""
        self.logger.info("Starting UDTUN Server...")
        self.logger.info(f"Local IP: {get_local_ip()}")
        self.logger.info(f"UDP Port Range: {config.udp_port_range[0]}-{config.udp_port_range[1]}")
        self.logger.info(f"Internal Port: {config.internal_port}")
        self.logger.info(f"TUN Interface: {config.tun_name} ({config.tun_ip})")
        
        # Setup packet handlers
        self.tun.set_packet_handler(self._handle_tun_packet)
        self.udp.set_receive_handler(self._handle_udp_packet)
        
        # Start components
        try:
            self.tun.start()
            self.udp.start()
        except Exception as e:
            self.logger.error(f"Failed to start server: {e}")
            self.cleanup()
            sys.exit(1)
        
        self.logger.info("Server started successfully")
        
        # Main loop
        self._main_loop()
    
    def _main_loop(self):
        """Main server loop"""
        last_stats_time = time.time()
        last_cleanup_time = time.time()
        
        while not self.shutdown.should_stop_now():
            try:
                # Update statistics periodically
                now = time.time()
                if now - last_stats_time > 10:
                    self._log_stats()
                    last_stats_time = now
                
                # Cleanup expired sessions
                if now - last_cleanup_time > 30:
                    cleaned = self.sessions.cleanup_expired()
                    if cleaned:
                        self.logger.debug(f"Cleaned up {cleaned} expired sessions")
                    last_cleanup_time = now
                    self.rate_limiter.cleanup()
                
                time.sleep(1)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}")
                with self.stats_lock:
                    self.stats['errors'] += 1
                time.sleep(1)
    
    def _handle_tun_packet(self, ip_packet: bytes):
        """Handle packet from TUN (to be sent to client)"""
        if len(ip_packet) < 20:
            return
        
        # Extract destination IP from packet
        dest_ip = ".".join(str(b) for b in ip_packet[16:20])
        
        # Find session by TUN IP
        target_session = None
        for session in self.sessions.sessions.values():
            if session.tun_ip == dest_ip:
                target_session = session
                break
        
        if not target_session:
            return
        
        # Encode and send via UDP
        encoded = self.udp.encode_packet(ip_packet)
        self.udp.send_packet(encoded, target_session.client_addr)
        
        # Update statistics
        with self.stats_lock:
            self.stats['packets_out'] += 1
            self.stats['bytes_out'] += len(encoded)
            if target_session:
                target_session.packets_sent += 1
                target_session.bytes_sent += len(encoded)
    
    def _handle_udp_packet(self, udp_packet: bytes, addr: Tuple[str, int]):
        """Handle packet from UDP (to be sent to TUN)"""
        # Rate limiting
        if not self.rate_limiter.check(addr):
            return
        
        # Decode packet
        ip_packet, seq, session_id = self.udp.decode_packet(udp_packet)
        
        if not ip_packet:
            return
        
        # Anti-replay check
        if not self.udp.check_replay(addr, seq):
            return
        
        # Get or create session
        session = self.sessions.get_session(addr)
        if not session:
            session = self.sessions.create_session(addr)
            self.logger.info(f"New session from {addr[0]}:{addr[1]} -> TUN IP: {session.tun_ip}")
        
        # Write to TUN
        self.tun.write_packet(ip_packet)
        
        # Update statistics
        with self.stats_lock:
            self.stats['packets_in'] += 1
            self.stats['bytes_in'] += len(udp_packet)
            session.packets_received += 1
            session.bytes_received += len(udp_packet)
    
    def _log_stats(self):
        """Log server statistics"""
        with self.stats_lock:
            active_sessions = self.sessions.get_active_count()
            
            self.logger.info(
                f"Stats: Sessions={active_sessions} | "
                f"In={self.stats['packets_in']}/{self.stats['bytes_in']>>10}KB | "
                f"Out={self.stats['packets_out']}/{self.stats['bytes_out']>>10}KB | "
                f"Errors={self.stats['errors']}"
            )
    
    def cleanup(self):
        """Cleanup resources"""
        self.logger.info("Shutting down server...")
        
        self.udp.stop()
        self.tun.stop()
        
        # Remove TUN interface
        os.system(f"ip link delete {config.tun_name} 2>/dev/null")
        
        self.logger.info("Server shutdown complete")

def main():
    """Main entry point"""
    # Load configuration
    if len(sys.argv) > 1:
        load_config(sys.argv[1])
    else:
        load_config()
    
    # Create and start server
    server = UDTUNServer()
    server.start()

if __name__ == "__main__":
    main()
