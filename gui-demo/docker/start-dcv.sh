#!/bin/bash
set -e

# Start D-Bus system bus (required by DCV)
mkdir -p /run/dbus
dbus-daemon --system --fork

# Start the DCV server
/usr/bin/dcvserver -d --service &
DCV_PID=$!

# Wait for DCV server to be ready
echo "Waiting for DCV server..."
for i in $(seq 1 30); do
    if dcv list-sessions &>/dev/null; then
        echo "DCV server is ready."
        break
    fi
    sleep 1
done

# Create a virtual session with DCV-GL off (avoids XFCE segfaults from GL interception)
dcv create-session \
    --type virtual \
    --owner rockyuser \
    --user rockyuser \
    --init /usr/libexec/dcv/dcvstartxfce \
    --gl off \
    rockyuser-session

echo "============================================"
echo " DCV session ready — connect on port 8443"
echo " User: rockyuser / Password: rocky"
echo "============================================"

# Keep container alive
wait $DCV_PID
