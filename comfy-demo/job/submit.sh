#!/bin/bash
# Submit ComfyUI Wan 2.2 S2V batch render to Deadline Cloud with SSM access.
# Creates an SSM hybrid activation, then submits the job bundle.
#
# Required env vars:
#   FARM_ID   — Deadline Cloud farm ID (farm-xxx)
#   QUEUE_ID  — Deadline Cloud queue ID (queue-xxx)
#
# Usage:
#   FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh [--show]
#
# Optional env vars:
#   WORKFLOW       — path to ComfyUI API workflow JSON
#   IMAGE          — path to reference image
#   AUDIO          — path to audio file
#   ECR_REGISTRY   — ECR registry URL (auto-detected if not set)
#   DOCKER_REPO    — ECR repository name (default: comfyui-wan22-s2v)
#   DOCKER_TAG     — Docker image tag (default: latest)
#   SESSION_MINUTES — minutes to keep SSM alive after render (default: 120, 0 to skip)
#   IAM_ROLE       — SSM service role name (default: SSMServiceRole)
#   COMFYUI_PORT   — ComfyUI port (default: 8188)

set -e

# Parse --show flag from any position
SHOW_SECRET=false
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--show" ]; then
    SHOW_SECRET=true
  else
    ARGS+=("$arg")
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
FARM_ID="${FARM_ID:-}"
QUEUE_ID="${QUEUE_ID:-}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
ECR_REGISTRY="${ECR_REGISTRY:-}"
DOCKER_REPO="${DOCKER_REPO:-comfyui-wan22-s2v}"
DOCKER_TAG="${DOCKER_TAG:-latest}"
SESSION_MINUTES="${SESSION_MINUTES:-120}"
IAM_ROLE="${IAM_ROLE:-SSMServiceRole}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

# Input files
WORKFLOW="${WORKFLOW:-${SCRIPT_DIR}/../comfy-dag-api.json}"
IMAGE="${IMAGE:-${SCRIPT_DIR}/../image.jpg}"
AUDIO="${AUDIO:-${SCRIPT_DIR}/../mary-had-a-little-lamb.mp3}"

if [ -z "$FARM_ID" ] || [ -z "$QUEUE_ID" ]; then
  echo "Error: FARM_ID and QUEUE_ID must be set"
  echo ""
  echo "Usage:"
  echo "  FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh [--show]"
  echo ""
  echo "Optional env vars:"
  echo "  WORKFLOW=path/to/workflow.json"
  echo "  IMAGE=path/to/image.jpg"
  echo "  AUDIO=path/to/audio.mp3"
  echo "  ECR_REGISTRY=... DOCKER_REPO=... DOCKER_TAG=..."
  echo "  SESSION_MINUTES=120  (0 to skip SSM session after render)"
  echo "  IAM_ROLE=SSMServiceRole"
  echo "  COMFYUI_PORT=8188"
  exit 1
fi

# Validate inputs exist
for f in "$WORKFLOW" "$IMAGE" "$AUDIO"; do
  if [ ! -f "$f" ]; then
    echo "Error: Input file not found: $f"
    exit 1
  fi
done

# Auto-detect ECR registry from current account if not set
if [ -z "$ECR_REGISTRY" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "${REGION}" 2>/dev/null)
  if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Could not detect AWS account ID. Set ECR_REGISTRY explicitly."
    exit 1
  fi
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
fi

echo "=============================================="
echo "ComfyUI Wan 2.2 S2V Batch — Job Submission"
echo "=============================================="
echo "Farm:     $FARM_ID"
echo "Queue:    $QUEUE_ID"
echo "Image:    $ECR_REGISTRY/$DOCKER_REPO:$DOCKER_TAG"
echo "Region:   $REGION"
echo "Workflow: $WORKFLOW"
echo "Image:    $IMAGE"
echo "Audio:    $AUDIO"
echo "SSM:      ${SESSION_MINUTES} min post-render"
echo "Port:     $COMFYUI_PORT"
echo ""

# --- Create SSM hybrid activation ---
echo "Creating SSM hybrid activation..."
ACTIVATION=$(aws ssm create-activation \
  --iam-role "${IAM_ROLE}" \
  --registration-limit 1 \
  --default-instance-name "deadline-comfyui-batch" \
  --region "${REGION}" \
  --output json)

cat > /tmp/parse_activation.py << 'PYEOF'
import json, sys
data = json.load(sys.stdin)
print(data["ActivationCode"])
print(data["ActivationId"])
PYEOF

ACTIVATION_CODE=$(echo "$ACTIVATION" | python3 /tmp/parse_activation.py | sed -n '1p')
ACTIVATION_ID=$(echo "$ACTIVATION" | python3 /tmp/parse_activation.py | sed -n '2p')
rm -f /tmp/parse_activation.py

if [ -z "$ACTIVATION_CODE" ] || [ -z "$ACTIVATION_ID" ]; then
  echo "ERROR: Failed to create SSM activation"
  echo "Response: $ACTIVATION"
  exit 1
fi

echo "Activation created:"
if [ "$SHOW_SECRET" = true ]; then
  echo "  Code: ${ACTIVATION_CODE}"
else
  echo "  Code: ${ACTIVATION_CODE:0:4}****"
fi
echo "  ID:   ${ACTIVATION_ID}"
echo ""

# --- Submit the Deadline Cloud job ---
echo "Submitting Deadline Cloud job..."
deadline bundle submit "${SCRIPT_DIR}" \
    --farm-id "$FARM_ID" \
    --queue-id "$QUEUE_ID" \
    --name "Wan22-S2V-Render-$(date +%Y%m%d-%H%M%S)" \
    --max-retries-per-task 1 \
    --yes \
    --parameter "ECR_REGISTRY=$ECR_REGISTRY" \
    --parameter "COMFYUI_REPOSITORY=$DOCKER_REPO" \
    --parameter "COMFYUI_TAG=$DOCKER_TAG" \
    --parameter "ActivationCode=${ACTIVATION_CODE}" \
    --parameter "ActivationId=${ACTIVATION_ID}" \
    --parameter "AWS_REGION=${REGION}" \
    --parameter "SessionMinutes=${SESSION_MINUTES}" \
    --parameter "COMFYUI_PORT=${COMFYUI_PORT}" \
    --parameter "WorkflowFile=$WORKFLOW" \
    --parameter "InputImage=$IMAGE" \
    --parameter "InputAudio=$AUDIO"

echo ""
echo "Job submitted. Watch the Deadline Cloud job log for the SSM connection command."
echo ""
echo "Once you see the mi-XXXXXXX ID in the log, connect with:"
echo ""
echo "  aws ssm start-session --target mi-XXXXXXX --region ${REGION} \\"
echo "    --document-name AWS-StartPortForwardingSession \\"
echo "    --parameters '{\"portNumber\":[\"${COMFYUI_PORT}\"],\"localPortNumber\":[\"${COMFYUI_PORT}\"]}'"
echo ""
echo "Then open http://localhost:${COMFYUI_PORT} in your browser."
echo "=============================================="
