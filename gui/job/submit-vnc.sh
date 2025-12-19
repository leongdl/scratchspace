#!/bin/bash
# Submit the VNC Desktop job to Deadline Cloud

# Configuration
FARM_ID="farm-fd8e9a84d9c04142848c6ea56c9d7568"
QUEUE_ID="queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38"

# Optional: Override parameters
EC2_PROXY_HOST="${EC2_PROXY_HOST:-10.0.0.65}"
SESSION_DURATION="${SESSION_DURATION:-3600}"

echo "Submitting VNC Desktop job..."
echo "Farm: $FARM_ID"
echo "Queue: $QUEUE_ID"
echo "EC2 Proxy: $EC2_PROXY_HOST"
echo "Session Duration: $SESSION_DURATION seconds"

deadline bundle submit . \
    --farm-id "$FARM_ID" \
    --queue-id "$QUEUE_ID" \
    --max-retries-per-task 1 \
    --name "Rocky-VNC-Desktop" \
    --parameter "EC2_PROXY_HOST=$EC2_PROXY_HOST" \
    --parameter "SESSION_DURATION=$SESSION_DURATION"
