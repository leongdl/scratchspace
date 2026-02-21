#!/bin/bash

# Start VNC server
su - rockyuser -c "vncserver :1 -geometry 1280x800 -depth 24"

# Wait for VNC to be ready
sleep 2

# Start websockify in background and keep container alive
websockify --web /usr/share/novnc 6080 localhost:5901 &

# Keep container running
wait
