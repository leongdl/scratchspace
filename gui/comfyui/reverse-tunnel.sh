#!/bin/bash
# Reverse SSH Tunnel for ComfyUI access via EC2 Proxy
# This allows accessing ComfyUI running on Deadline workers through an EC2 bastion

set -e

EC2_PROXY_HOST="${EC2_PROXY_HOST:-}"
EC2_PROXY_PORT="${EC2_PROXY_PORT:-6688}"
EC2_PROXY_USER="${EC2_PROXY_USER:-ec2-user}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/home/comfyui/.ssh/id_rsa}"
LOCAL_PORT="${COMFYUI_PORT:-8188}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"
MAX_RETRIES="${MAX_RETRIES:-30}"

if [ -z "${EC2_PROXY_HOST}" ]; then
    echo "EC2_PROXY_HOST not set, skipping reverse tunnel"
    exit 0
fi

# Generate SSH key if it doesn't exist
if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "Generating SSH key..."
    mkdir -p "$(dirname ${SSH_KEY_PATH})"
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "comfyui-worker"
    chown -R comfyui:comfyui "$(dirname ${SSH_KEY_PATH})"
    echo "=== PUBLIC KEY (add to EC2 authorized_keys) ==="
    cat "${SSH_KEY_PATH}.pub"
    echo "================================================"
fi

# Wait for SSH key to be authorized (if using dynamic key distribution)
if [ -n "${WAIT_FOR_AUTH}" ]; then
    echo "Waiting for SSH authorization..."
    sleep "${WAIT_FOR_AUTH}"
fi

echo "Establishing reverse tunnel: localhost:${LOCAL_PORT} -> ${EC2_PROXY_HOST}:${EC2_PROXY_PORT}"

retry_count=0
while [ ${retry_count} -lt ${MAX_RETRIES} ]; do
    ssh -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -i "${SSH_KEY_PATH}" \
        -N -R "${EC2_PROXY_PORT}:localhost:${LOCAL_PORT}" \
        "${EC2_PROXY_USER}@${EC2_PROXY_HOST}" &
    
    SSH_PID=$!
    
    # Wait for SSH to establish or fail
    sleep 5
    
    if kill -0 ${SSH_PID} 2>/dev/null; then
        echo "Reverse tunnel established successfully"
        wait ${SSH_PID}
        echo "Tunnel disconnected, reconnecting..."
    else
        echo "Failed to establish tunnel, retrying in ${RETRY_INTERVAL}s..."
    fi
    
    retry_count=$((retry_count + 1))
    sleep ${RETRY_INTERVAL}
done

echo "Max retries reached, giving up on reverse tunnel"
exit 1
