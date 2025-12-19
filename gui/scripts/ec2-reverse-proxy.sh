#!/bin/bash
# EC2 Reverse Proxy Script
# 
# Listens on port 6688 (for Deadline SMF connections) and forwards to port 6080
# Uses verbose mode to show all traffic for debugging

set -e

LISTEN_PORT="${LISTEN_PORT:-6688}"
FORWARD_PORT="${FORWARD_PORT:-6080}"

echo "=============================================="
echo "EC2 Reverse Proxy (Debug Mode)"
echo "=============================================="
echo "Listen port: $LISTEN_PORT (Deadline SMF connects here)"
echo "Forward to:  localhost:$FORWARD_PORT (noVNC)"
echo "=============================================="
echo ""

# Check if socat is installed
if ! command -v socat &> /dev/null; then
    echo "socat not found. Installing..."
    sudo yum install -y socat || sudo dnf install -y socat || sudo apt-get install -y socat
fi

# Kill any existing socat process on the listen port
pkill -f "socat.*:$LISTEN_PORT" 2>/dev/null || true

echo "Starting socat proxy with verbose logging..."
echo "Press Ctrl+C to stop"
echo ""
echo "--- Traffic Log ---"

# Start socat with verbose options:
# -d -d -d = maximum debug verbosity
# -v = dump data in hex
# TCP-LISTEN:6688,fork,reuseaddr = listen on 6688, fork for each connection
# TCP:localhost:6080 = forward to localhost:6080
socat -d -d -d -v \
    TCP-LISTEN:$LISTEN_PORT,fork,reuseaddr \
    TCP:localhost:$FORWARD_PORT
