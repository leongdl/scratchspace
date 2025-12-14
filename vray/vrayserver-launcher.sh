#!/bin/bash
# VRay Server Launcher

export PATH=/opt/vray/bin:$PATH
export LD_LIBRARY_PATH=/opt/vray/lib:$LD_LIBRARY_PATH

if [ -f /opt/vray/bin/vrayserver ]; then
    /opt/vray/bin/vrayserver "$@"
else
    echo "VRay server binary not found"
    exit 1
fi