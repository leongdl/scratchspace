#!/bin/bash
# Create SSM tunnel from Mac to EC2 proxy for ComfyUI access

INSTANCE_ID="${INSTANCE_ID:-i-0dafdfc660885e366}"
INSTANCE_REGION="${INSTANCE_REGION:-us-west-2}"
LOCAL_PORT="${LOCAL_PORT:-8188}"
REMOTE_PORT="${REMOTE_PORT:-8188}"

echo "Creating SSM tunnel to ComfyUI"
echo "  Instance: ${INSTANCE_ID}"
echo "  Region: ${INSTANCE_REGION}"
echo "  Local port: ${LOCAL_PORT}"

aws ssm start-session \
    --target "${INSTANCE_ID}" \
    --region "${INSTANCE_REGION}" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"${REMOTE_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
