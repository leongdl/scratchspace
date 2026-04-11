#!/bin/bash
set -e

# ComfyUI Startup Script for Deadline Cloud Workers

COMFYUI_DIR="/opt/comfyui"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
COMFYUI_LISTEN="${COMFYUI_LISTEN:-0.0.0.0}"
PYTHON_CMD="${PYTHON_CMD:-python3.12}"

echo "=== ComfyUI Startup ==="
echo "Port: ${COMFYUI_PORT}"
echo "Listen: ${COMFYUI_LISTEN}"

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
# Auto-detect VRAM and enable --lowvram for GPUs with <=24GB (e.g. L4, A10G)
# The Wan 2.2 S2V 14B fp8 model needs ~28GB VRAM at peak; --lowvram offloads
# model chunks to CPU RAM to fit on smaller GPUs at the cost of speed.
if [ "${LOW_VRAM}" = "true" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --lowvram"
elif [ "${HIGH_VRAM}" = "true" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS} --highvram"
elif [ "${AUTO_VRAM}" != "false" ]; then
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "${VRAM_MB}" ] && [ "${VRAM_MB}" -le 24576 ]; then
        echo "Auto-detected ${VRAM_MB}MB VRAM (<=24GB) — enabling --lowvram"
        COMFYUI_ARGS="${COMFYUI_ARGS} --lowvram"
    elif [ -n "${VRAM_MB}" ]; then
        echo "Auto-detected ${VRAM_MB}MB VRAM (>24GB) — using normal VRAM mode"
    fi
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
    runuser -u comfyui -- bash -c "cd ${COMFYUI_DIR} && ${PYTHON_CMD} main.py ${COMFYUI_ARGS}"
else
    cd ${COMFYUI_DIR} && ${PYTHON_CMD} main.py ${COMFYUI_ARGS}
fi
