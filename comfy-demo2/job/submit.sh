#!/bin/bash
# Submit ComfyUI Wan 2.2 S2V batch render to Deadline Cloud
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration — override with env vars
FARM_ID="${FARM_ID:-}"
QUEUE_ID="${QUEUE_ID:-}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
ECR_REGISTRY="${ECR_REGISTRY:-257639634185.dkr.ecr.us-west-2.amazonaws.com}"
DOCKER_REPO="${DOCKER_REPO:-comfyui-wan22-s2v}"
DOCKER_TAG="${DOCKER_TAG:-latest}"

# Input files — defaults point to sibling files in comfy-demo/
WORKFLOW="${WORKFLOW:-${SCRIPT_DIR}/../comfy-dag-api.json}"
IMAGE="${IMAGE:-${SCRIPT_DIR}/../image.jpg}"
AUDIO="${AUDIO:-${SCRIPT_DIR}/../mary-had-a-little-lamb.mp3}"

if [ -z "$FARM_ID" ] || [ -z "$QUEUE_ID" ]; then
  echo "Error: FARM_ID and QUEUE_ID must be set"
  echo ""
  echo "Usage:"
  echo "  FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh"
  echo ""
  echo "Optional overrides:"
  echo "  WORKFLOW=path/to/workflow.json"
  echo "  IMAGE=path/to/image.jpg"
  echo "  AUDIO=path/to/audio.mp3"
  echo "  ECR_REGISTRY=... DOCKER_REPO=... DOCKER_TAG=..."
  exit 1
fi

# Validate inputs exist
for f in "$WORKFLOW" "$IMAGE" "$AUDIO"; do
  if [ ! -f "$f" ]; then
    echo "Error: Input file not found: $f"
    exit 1
  fi
done

echo "Submitting ComfyUI Wan 2.2 S2V batch job..."
echo "  Farm:     $FARM_ID"
echo "  Queue:    $QUEUE_ID"
echo "  Image:    $ECR_REGISTRY/$DOCKER_REPO:$DOCKER_TAG"
echo "  Workflow: $WORKFLOW"
echo "  Image:    $IMAGE"
echo "  Audio:    $AUDIO"

deadline bundle submit "${SCRIPT_DIR}" \
    --farm-id "$FARM_ID" \
    --queue-id "$QUEUE_ID" \
    --name "Wan22-S2V-Render-$(date +%Y%m%d-%H%M%S)" \
    --max-retries-per-task 1 \
    --yes \
    --parameter "ECR_REGISTRY=$ECR_REGISTRY" \
    --parameter "COMFYUI_REPOSITORY=$DOCKER_REPO" \
    --parameter "COMFYUI_TAG=$DOCKER_TAG" \
    --parameter "WorkflowFile=$WORKFLOW" \
    --parameter "InputImage=$IMAGE" \
    --parameter "InputAudio=$AUDIO"

echo "Job submitted!"
