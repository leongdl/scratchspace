#!/bin/bash
# Submit the VNC Desktop job to Deadline Cloud

# Configuration
FARM_ID="farm-6c262cf737de4cb9b0c46f55f71cdaff"
QUEUE_ID="queue-6c7f40e315a44d0abb2cc169c0b85bb9"
SESSION_DURATION="${SESSION_DURATION:-3600}"
ECR_REGISTRY="${ECR_REGISTRY:-257639634185.dkr.ecr.us-west-2.amazonaws.com}"
DOCKER_REPO="${DOCKER_REPO:-desktop-demo}"
DOCKER_TAG="${DOCKER_TAG:-rocky-vnc}"
EC2_PROXY_HOST="${EC2_PROXY_HOST:-rcfg-0a8ab60ee0c8594b6.resource-endpoints.deadline.us-west-2.amazonaws.com}"

# Check SSH tunnel key exists (required as job attachment)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/vnc_tunnel_key" ]; then
  echo "Error: vnc_tunnel_key not found in $SCRIPT_DIR"
  echo ""
  echo "Generate it by running from the gui-demo root:"
  echo "  bash generate_tunnel_key.sh"
  echo ""
  echo "Then add the public key to the EC2 bastion:"
  echo "  cat job/vnc_tunnel_key.pub >> /home/ssm-user/.ssh/authorized_keys"
  exit 1
fi

echo "Submitting VNC Desktop job..."
echo "Farm: $FARM_ID"
echo "Queue: $QUEUE_ID"
echo "Docker Image: $ECR_REGISTRY/$DOCKER_REPO:$DOCKER_TAG"
echo "EC2 Proxy: $EC2_PROXY_HOST"
echo "Session Duration: $SESSION_DURATION seconds"

deadline bundle submit . \
    --farm-id "$FARM_ID" \
    --queue-id "$QUEUE_ID" \
    --max-retries-per-task 1 \
    --name "Rocky-VNC-Desktop" \
    --parameter "ECR_REGISTRY=$ECR_REGISTRY" \
    --parameter "VNC_REPOSITORY=$DOCKER_REPO" \
    --parameter "VNC_TAG=$DOCKER_TAG" \
    --parameter "EC2_PROXY_HOST=$EC2_PROXY_HOST" \
    --parameter "SESSION_DURATION=$SESSION_DURATION"
