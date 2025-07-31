#!/bin/bash
# Simple script to start the Docker container and test V-Ray plugin loading

set -e  # Exit on error

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Configuration
IMAGE_NAME="maya-vray:latest"
WORK_DIR="$(pwd)/vray_simple_test"

# Create output directory
mkdir -p "$WORK_DIR"

echo "=== Building Docker container with V-Ray ==="
docker build -t "$IMAGE_NAME" -f Dockerfile.vray .

echo "=== Checking V-Ray module file ==="
docker run --rm "$IMAGE_NAME" bash -c "ls -la /usr/autodesk/vray4maya2025/maya_root/modules || echo 'V-Ray module directory not found'"

echo "=== Starting container and testing V-Ray plugin loading ==="
docker run --rm \
  -v "$WORK_DIR:/work" \
  -w /work \
  "$IMAGE_NAME" \
  /usr/autodesk/maya/bin/maya -batch -command "print(\"Loading V-Ray plugin...\"); loadPlugin(\"vrayformaya\"); print(\"V-Ray plugin loaded successfully!\"); string \$version = \`pluginInfo -query -version vrayformaya\`; print(\"V-Ray version: \" + \$version); quit -f;"

echo ""
echo "=== Test complete! ==="
echo "If you see 'V-Ray plugin loaded successfully!' above, the test passed."
echo "Check the version number to confirm it's V-Ray Advanced 7.10.00"