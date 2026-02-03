#!/bin/bash
# Submit ComfyUI job to Deadline Cloud

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration (override with environment variables)
FARM_ID="${FARM_ID:-}"
QUEUE_ID="${QUEUE_ID:-}"
EC2_PROXY_HOST="${EC2_PROXY_HOST:-10.0.0.65}"
EC2_PROXY_PORT="${EC2_PROXY_PORT:-6688}"
SESSION_DURATION="${SESSION_DURATION:-3600}"
DOCKER_IMAGE="${DOCKER_IMAGE:-comfyui-rocky:latest}"
ENABLE_MANAGER="${ENABLE_MANAGER:-false}"
VRAM_MODE="${VRAM_MODE:-normal}"

if [ -z "${FARM_ID}" ] || [ -z "${QUEUE_ID}" ]; then
    echo "Error: FARM_ID and QUEUE_ID must be set"
    echo "Usage: FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit-comfyui.sh"
    exit 1
fi

echo "Submitting ComfyUI job to Deadline Cloud"
echo "  Farm: ${FARM_ID}"
echo "  Queue: ${QUEUE_ID}"
echo "  EC2 Proxy: ${EC2_PROXY_HOST}:${EC2_PROXY_PORT}"
echo "  Duration: ${SESSION_DURATION}s"
echo "  Image: ${DOCKER_IMAGE}"

deadline bundle submit "${SCRIPT_DIR}" \
    --farm-id "${FARM_ID}" \
    --queue-id "${QUEUE_ID}" \
    --name "ComfyUI Session $(date +%Y%m%d-%H%M%S)" \
    --parameter "SessionDuration=${SESSION_DURATION}" \
    --parameter "EC2ProxyHost=${EC2_PROXY_HOST}" \
    --parameter "EC2ProxyPort=${EC2_PROXY_PORT}" \
    --parameter "DockerImage=${DOCKER_IMAGE}" \
    --parameter "EnableManager=${ENABLE_MANAGER}" \
    --parameter "VRAMMode=${VRAM_MODE}"

echo "Job submitted! Connect via:"
echo "  1. Start SSM tunnel: aws ssm start-session --target <ec2-instance-id> --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8188\"],\"localPortNumber\":[\"8188\"]}'"
echo "  2. Open: http://localhost:8188"
