#!/bin/bash
# VRay Standalone Renderer Launcher

export PATH=/opt/vray/bin:$PATH
export LD_LIBRARY_PATH=/opt/vray/lib:$LD_LIBRARY_PATH
export QT_QPA_PLATFORM=offscreen

if [ -f /opt/vray/bin/vray.bin ]; then
    /opt/vray/bin/vray.bin "$@"
else
    echo "VRay binary not found"
    exit 1
fi