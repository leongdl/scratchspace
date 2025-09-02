#!/bin/bash

# Houdini RenderMan Docker Container Launcher
# This script starts the houdini-rdman container with proper configuration
#
# Usage:
#   ./run-houdini-rdman.sh                    # Start interactive bash shell
#   ./run-houdini-rdman.sh "hrender --help"   # Run specific command
#   ./run-houdini-rdman.sh "hrender -d /out/renderman1 /render/RMAN_test_02.hip"

# Set container name and image
CONTAINER_NAME="houdini-rdman"
IMAGE_NAME="houdini-rdman:latest"

# Get command to run (default to interactive bash)
COMMAND="${1:-/bin/bash}"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Error: Docker image '$IMAGE_NAME' not found."
    echo "Please build the image first using: docker build -f Dockerfile.houdini-rdman -t houdini-rdman:latest ."
    exit 1
fi

echo "Starting Houdini RenderMan container..."
echo "Container: $CONTAINER_NAME"
echo "Image: $IMAGE_NAME"
if [ "$COMMAND" != "/bin/bash" ]; then
    echo "Command: $COMMAND"
fi
echo ""

# Start container with Houdini environment setup
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    --network host \
    --ulimit stack=52428800 \
    --volume "$(pwd):/workspace" \
    --workdir /workspace \
    "$IMAGE_NAME" \
    bash -c "cd /opt/houdini && source ./houdini_setup_bash && \
    export SESI_LMHOST=localhost:1715 && \
    export VRAY_AUTH_CLIENT_FILE_PATH=\"/null\" && \
    export VRAY_AUTH_CLIENT_SETTINGS=\"licset://localhost:30304\" && \
    echo \"License environment configured:\" && \
    echo \"  SESI_LMHOST=\$SESI_LMHOST\" && \
    echo \"  VRAY_AUTH_CLIENT_FILE_PATH=\$VRAY_AUTH_CLIENT_FILE_PATH\" && \
    echo \"  VRAY_AUTH_CLIENT_SETTINGS=\$VRAY_AUTH_CLIENT_SETTINGS\" && \
    echo \"\" && \
    exec $COMMAND"

echo ""
echo "Container stopped."