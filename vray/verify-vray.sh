#!/bin/bash
# VRay Installation Verification

echo "=== VRay Standalone Installation Verification ==="
echo "VRay Path: /opt/vray"
echo ""

echo "Checking VRay binaries:"
if [ -f /opt/vray/bin/vray.bin ]; then
    echo "✓ VRay renderer found at /opt/vray/bin/vray.bin"
else
    echo "✗ VRay renderer not found"
fi

if [ -f /opt/vray/bin/vrayserver ]; then
    echo "✓ VRay server found at /opt/vray/bin/vrayserver"
else
    echo "✗ VRay server not found"
fi

echo ""
echo "Environment variables:"
echo "PATH includes VRay: $(echo $PATH | grep -o '/opt/vray/bin' || echo 'No')"
echo "LD_LIBRARY_PATH includes VRay: $(echo $LD_LIBRARY_PATH | grep -o '/opt/vray/lib' || echo 'No')"

echo ""
echo "VRay directory contents:"
ls -la /opt/vray/ 2>/dev/null || echo "VRay directory not found or empty"