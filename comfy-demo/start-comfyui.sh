#!/bin/bash
set -e

# ComfyUI Startup Script for Deadline Cloud Workers
# Supports reverse tunnel for remote access

COMFYUI_DIR="/opt/comfyui"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
COMFYUI_LISTEN="${COMFYUI_LISTEN:-0.0.0.0}"
PYTHON_CMD="${PYTHON_CMD:-python3.12}"

# Optional: Enable reverse tunnel to EC2 proxy
EC2_PROXY_HOST="${EC2_PROXY_HOST:-}"
EC2_PROXY_PORT="${EC2_PROXY_PORT:-6688}"
EC2_PROXY_USER="${EC2_PROXY_USER:-ec2-user}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/home/comfyui/.ssh/id_rsa}"

echo "=== ComfyUI Startup ==="
echo "Port: ${COMFYUI_PORT}"
echo "Listen: ${COMFYUI_LISTEN}"

# Start reverse tunnel if EC2 proxy is configured
if [ -n "${EC2_PROXY_HOST}" ]; then
    echo "Setting up reverse tunnel to ${EC2_PROXY_HOST}:${EC2_PROXY_PORT}"
    /reverse-tunnel.sh &
    TUNNEL_PID=$!
    echo "Reverse tunnel started (PID: ${TUNNEL_PID})"
fi

# Wait for any model downloads or initialization
if [ -n "${INIT_SCRIPT}" ] && [ -f "${INIT_SCRIPT}" ]; then
    echo "Running initialization script: ${INIT_SCRIPT}"
    bash "${INIT_SCRIPT}"
fi

# Start ComfyUI
cd "${COMFYUI_DIR}"

# Build command line arguments
COMFYUI_ARGS="--listen ${COMFYUI_LISTEN} --port ${COMFYUI_PORT}"

# Add preview method if specified
if [ -n "${PREVIEW_METHOD}" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --preview-method ${PREVIEW_METHOD}"
fi

# Add extra model paths if specified
if [ -f "/opt/comfyui/extra_model_paths.yaml" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --extra-model-paths-config /opt/comfyui/extra_model_paths.yaml"
fi

# Enable manager if requested
if [ "${ENABLE_MANAGER}" = "true" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --enable-manager"
fi

# GPU memory optimization flags
if [ "${LOW_VRAM}" = "true" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --lowvram"
elif [ "${HIGH_VRAM}" = "true" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --highvram"
fi

# CPU-only mode
if [ "${CPU_ONLY}" = "true" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --cpu"
fi

# Additional custom arguments
if [ -n "${EXTRA_ARGS}" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} ${EXTRA_ARGS}"
fi

echo "Starting ComfyUI with args: ${COMFYUI_ARGS}"

# Run as comfyui user if we're root, otherwise run directly
if [ "$(id -u)" = "0" ]; then
    # Use runuser instead of su (doesn't require PAM auth)
    runuser -u comfyui -- bash -c "cd ${COMFYUI_DIR} && ${PYTHON_CMD} main.py ${COMFYUI_ARGS}"
else
    cd ${COMFYUI_DIR} && ${PYTHON_CMD} main.py ${COMFYUI_ARGS}
fi
