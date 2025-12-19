#!/bin/bash
# Mac Tunnel Script
# Creates an SSM port forwarding session from your Mac to the EC2 proxy instance
# This forwards local port 6080 to the EC2 instance's port 6080

set -e

# Configuration - Update these values
INSTANCE_ID="${INSTANCE_ID:-i-0dafdfc660885e366}"
INSTANCE_REGION="${INSTANCE_REGION:-us-west-2}"
LOCAL_PORT="${LOCAL_PORT:-6080}"
REMOTE_PORT="${REMOTE_PORT:-6080}"

echo "=============================================="
echo "Mac to EC2 SSM Tunnel"
echo "=============================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $INSTANCE_REGION"
echo "Local Port: $LOCAL_PORT -> Remote Port: $REMOTE_PORT"
echo "=============================================="
echo ""
echo "After connection, access noVNC at: http://localhost:$LOCAL_PORT/vnc.html"
echo "VNC Password: password"
echo ""
echo "Starting SSM session..."

aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$INSTANCE_REGION" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
