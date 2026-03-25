#!/bin/bash
# Submit ComfyUI GUI session to Deadline Cloud with SSM port forwarding.
# Creates an SSM hybrid activation, then submits the job bundle.
#
# Usage:
#   ./submit.sh [session_minutes] [iam_role_name] [region] [--show]
#
# Examples:
#   ./submit.sh                              # 120 min, SSMServiceRole, us-west-2
#   ./submit.sh 240                          # 4 hours
#   ./submit.sh 120 MySSMRole us-east-1
#   ./submit.sh 120 SSMServiceRole us-west-2 --show   # print full activation code

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
FARM_ID="${FARM_ID:-farm-fd8e9a84d9c04142848c6ea56c9d7568}"
QUEUE_ID="${QUEUE_ID:-queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38}"
ECR_REGISTRY="${ECR_REGISTRY:-224071664257.dkr.ecr.us-west-2.amazonaws.com}"
DOCKER_REPO="${DOCKER_REPO:-sqex2}"
DOCKER_TAG="${DOCKER_TAG:-wans2v}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
