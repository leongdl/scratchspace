#!/bin/bash

# VRay Docker Container Build Script

set -e

CONTAINER_NAME="vray-standalone"
VRAY_INSTALLER="vraystd_adv_71000_centos7_clang-gcc-6.3"

echo "=== VRay Docker Container Build Script ==="
echo ""

# Check if VRay installer exists
if [ ! -f "$VRAY_INSTALLER" ]; then
    echo "❌ VRay installer not found: $VRAY_INSTALLER"
    echo ""
    echo "Please download the VRay installer from Chaos Group and place it in this directory:"
    echo "  - File: $VRAY_INSTALLER"
    echo "  - Location: $(pwd)/"
    echo ""
    echo "You can download it from: https://www.chaosgroup.com/vray/downloads"
    echo "(Requires Chaos Group account and valid license)"
    exit 1
fi

echo "✅ VRay installer found: $VRAY_INSTALLER"
echo ""

# Build the container
echo "🔨 Building VRay container..."
docker build -t "$CONTAINER_NAME" .

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo ""
    echo "Container name: $CONTAINER_NAME"
    echo ""
    echo "Next steps:"
    echo "  1. Verify installation: docker run --rm $CONTAINER_NAME verify-vray"
    echo "  2. Test rendering: docker run --rm -v /path/to/scenes:/render $CONTAINER_NAME vray scene.vrscene"
    echo "  3. Start server: docker run --rm -p 20204:20204 $CONTAINER_NAME vrayserver"
    echo ""
else
    echo ""
    echo "❌ Build failed!"
    echo "Check the error messages above for details."
    exit 1
fi