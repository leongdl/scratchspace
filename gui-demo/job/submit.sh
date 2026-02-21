#!/bin/bash
# Submit the VNC Desktop job to Deadline Cloud

# Configuration
FARM_ID="farm-fd8e9a84d9c04142848c6ea56c9d7568"
QUEUE_ID="queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38"
SESSION_DURATION="${SESSION_DURATION:-3600}"
ECR_REGISTRY="${ECR_REGISTRY:-224071664257.dkr.ecr.us-west-2.amazonaws.com}"
DOCKER_REPO="${DOCKER_REPO:-sqex2}"
DOCKER_TAG="${DOCKER_TAG:-rocky-vnc}"

# EC2_PROXY_HOST is the VPC Lattice resource endpoint — must be set by the user.
# Find it in resources.json after running setup_infrastructure.py, or in the
# Deadline console under your fleet's VPC resource endpoints.
# Example: rcfg-xxxxxxxxx.resource-endpoints.deadline.us-west-2.amazonaws.com
if [ -z "${EC2_PROXY_HOST}" ]; then
  echo "Error: EC2_PROXY_HOST is not set."
  echo ""
  echo "Set it to your VPC Lattice resource endpoint, e.g.:"
  echo "  export EC2_PROXY_HOST=rcfg-xxxxx.resource-endpoints.deadline.us-west-2.amazonaws.com"
  echo ""
  echo "You can find this in gui-demo/resources.json after running setup_infrastructure.py"
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
