#!/usr/bin/env python3
"""
Graceful Shutdown Handler - WHISPER Tunnel Server
"""

import signal
import sys
import threading

class GracefulShutdown:
    """Handle graceful shutdown"""
    
    def __init__(self):
        self.should_stop = False
        self.lock = threading.Lock()
        self.callbacks = []
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        print(f"\nReceived shutdown signal ({signum})")
        with self.lock:
            self.should_stop = True
        
        # Call registered callbacks
        for callback in self.callbacks:
            try:
                callback()
            except Exception as e:
                print(f"Error in shutdown callback: {e}")
    
    def register_callback(self, callback):
        """Register callback for shutdown"""
        with self.lock:
            self.callbacks.append(callback)
    
    def should_exit(self) -> bool:
        """Check if should exit"""
        with self.lock:
            return self.should_stop
    
    def wait_for_exit(self, check_interval: float = 0.5):
        """Wait for exit signal"""
        while not self.should_exit():
            try:
                signal.pause()
            except KeyboardInterrupt:
                self._signal_handler(signal.SIGINT, None)
            except Exception:
                pass
