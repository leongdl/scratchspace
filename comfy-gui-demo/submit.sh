#!/bin/bash
# Submit ComfyUI GUI session to Deadline Cloud with SSM port forwarding.
# Creates an SSM hybrid activation, then submits the job bundle.
#
# Required env vars:
#   FARM_ID   — Deadline Cloud farm ID (farm-xxx)
#   QUEUE_ID  — Deadline Cloud queue ID (queue-xxx)
#
# Usage:
#   FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh [session_minutes] [iam_role_name] [region] [--show]
#
# Examples:
#   FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh                    # 120 min, SSMServiceRole, us-west-2
#   FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh 240                # 4 hours
#   FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh 120 MySSMRole us-east-1
#   FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh 120 SSMServiceRole us-west-2 --show

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

SESSION_MINUTES="${ARGS[0]:-120}"
IAM_ROLE="${ARGS[1]:-SSMServiceRole}"
REGION="${ARGS[2]:-us-west-2}"
FARM_ID="${FARM_ID:-}"
QUEUE_ID="${QUEUE_ID:-}"
ECR_REGISTRY="${ECR_REGISTRY:-}"
DOCKER_REPO="${DOCKER_REPO:-}"
DOCKER_TAG="${DOCKER_TAG:-}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$FARM_ID" ] || [ -z "$QUEUE_ID" ]; then
  echo "Error: FARM_ID and QUEUE_ID must be set"
  echo ""
  echo "Usage:"
  echo "  FARM_ID=farm-xxx QUEUE_ID=queue-xxx ./submit.sh [session_minutes] [iam_role] [region] [--show]"
  echo ""
  echo "Optional env vars:"
  echo "  ECR_REGISTRY  — ECR registry URL (default: <account>.dkr.ecr.<region>.amazonaws.com)"
  echo "  DOCKER_REPO   — ECR repository name (default: comfyui)"
  echo "  DOCKER_TAG    — Docker image tag (default: latest)"
  echo "  COMFYUI_PORT  — ComfyUI port (default: 8188)"
  exit 1
fi

# Auto-detect ECR registry from current account if not set
if [ -z "$ECR_REGISTRY" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "${REGION}" 2>/dev/null)
  if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Could not detect AWS account ID. Set ECR_REGISTRY explicitly."
    exit 1
  fi
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
fi
DOCKER_REPO="${DOCKER_REPO:-comfyui}"
DOCKER_TAG="${DOCKER_TAG:-latest}"

echo "=============================================="
echo "ComfyUI GUI Session — Job Submission"
echo "=============================================="
echo "Session:  ${SESSION_MINUTES} minutes"
echo "IAM Role: ${IAM_ROLE}"
echo "Region:   ${REGION}"
echo "Farm:     ${FARM_ID}"
echo "Queue:    ${QUEUE_ID}"
echo "Image:    ${ECR_REGISTRY}/${DOCKER_REPO}:${DOCKER_TAG}"
echo "Port:     ${COMFYUI_PORT}"
echo ""

# --- Create SSM hybrid activation ---
echo "Creating SSM hybrid activation..."
ACTIVATION=$(aws ssm create-activation \
  --iam-role "${IAM_ROLE}" \
  --registration-limit 1 \
  --default-instance-name "deadline-comfyui-ssm" \
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
deadline bundle submit "${SCRIPT_DIR}/job" \
  --farm-id "${FARM_ID}" \
  --queue-id "${QUEUE_ID}" \
  --name "ComfyUI-GUI-$(date +%Y%m%d-%H%M%S)" \
  --max-retries-per-task 1 \
  --yes \
  --parameter "ActivationCode=${ACTIVATION_CODE}" \
  --parameter "ActivationId=${ACTIVATION_ID}" \
  --parameter "AWS_REGION=${REGION}" \
  --parameter "SessionMinutes=${SESSION_MINUTES}" \
  --parameter "ECR_REGISTRY=${ECR_REGISTRY}" \
  --parameter "COMFYUI_REPOSITORY=${DOCKER_REPO}" \
  --parameter "COMFYUI_TAG=${DOCKER_TAG}" \
  --parameter "COMFYUI_PORT=${COMFYUI_PORT}"

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
