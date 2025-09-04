#!/bin/bash

# Houdini RenderMan Docker Container Launcher
# This script starts the houdini-rdman container with proper configuration
# Includes RenderMan for Houdini plugin and RenderMan ProServer
#
# Usage:
#   ./run-houdini-rdman.sh                    # Start interactive bash shell (auto-tests prman)
#   ./run-houdini-rdman.sh "hrender --help"   # Run specific command
#   ./run-houdini-rdman.sh "hrender -d /out/renderman1 /render/RMAN_test_02.hip"
#   ./run-houdini-rdman.sh "test-renderman"   # Test RenderMan ProServer installation
#   ./run-houdini-rdman.sh "prman -version"   # Test prman directly
#
# The script automatically sets up all RenderMan environment variables and tests prman on startup

# Set container name and image
CONTAINER_NAME="houdini-rdman-rhel"
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
    echo "Please build the image first using: docker build -f Dockerfile.houdini-rdman-RHEL -t houdini-rdman:latest ."
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
    export PIXAR_LICENSE_FILE=\"9010@localhost\" && \
    export RMANTREE=/opt/pixar/RenderManProServer-26.3 && \
    export RFHTREE=/opt/pixar/RenderManForHoudini-26.3 && \
    export RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/openvdb && \
    export HOUDINI_PATH=/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896:/opt/houdini/houdini:/opt/houdini && \
    export PATH=\$RMANTREE/bin:\$PATH && \
    export LD_LIBRARY_PATH=\$RMANTREE/lib:\$LD_LIBRARY_PATH && \
    export QT_QPA_PLATFORM=offscreen && \
    export HOUDINI_DSO_ERROR=0 && \
    echo \"License environment configured:\" && \
    echo \"  SESI_LMHOST=\$SESI_LMHOST\" && \
    echo \"  VRAY_AUTH_CLIENT_FILE_PATH=\$VRAY_AUTH_CLIENT_FILE_PATH\" && \
    echo \"  VRAY_AUTH_CLIENT_SETTINGS=\$VRAY_AUTH_CLIENT_SETTINGS\" && \
    echo \"  PIXAR_LICENSE_FILE=\$PIXAR_LICENSE_FILE\" && \
    echo \"RenderMan environment configured:\" && \
    echo \"  RMANTREE=\$RMANTREE\" && \
    echo \"  RFHTREE=\$RFHTREE\" && \
    echo \"  RMAN_PROCEDURALPATH=\$RMAN_PROCEDURALPATH\" && \
    echo \"  HOUDINI_PATH=\$HOUDINI_PATH\" && \
    echo \"\" && \
    exec $COMMAND"

echo ""
echo "Container stopped."