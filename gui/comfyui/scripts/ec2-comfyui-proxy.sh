#!/bin/bash
# Run socat proxy on EC2 to forward ComfyUI traffic
# The reverse tunnel from the worker connects to port 6688
# socat forwards external connections on 8188 to the tunnel on 6688

LISTEN_PORT="${LISTEN_PORT:-8188}"
TUNNEL_PORT="${TUNNEL_PORT:-6688}"

echo "Starting ComfyUI proxy"
echo "  Listen port: ${LISTEN_PORT} (for SSM tunnel)"
echo "  Tunnel port: ${TUNNEL_PORT} (from worker reverse tunnel)"
echo ""
echo "Connect from Mac using:"
echo "  ./mac-tunnel.sh"
echo "Then open: http://localhost:8188"
echo ""
echo "Press Ctrl+C to stop"

socat TCP-LISTEN:${LISTEN_PORT},fork,reuseaddr TCP:localhost:${TUNNEL_PORT}
