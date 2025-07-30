#!/bin/bash

# License server configuration for Houdini and VRay rendering
# This script sets up the necessary environment variables for license servers

echo "Setting up license server environment variables..."

# Houdini license server configuration
# Points to the license server through SSH tunnel on localhost:30304
export SESI_LMHOST=localhost:1715

# VRay license server configuration
# Disable VRay auth client file and use localhost license server
export VRAY_AUTH_CLIENT_FILE_PATH="/null"
export VRAY_AUTH_CLIENT_SETTINGS="licset://localhost:30304"

echo "License environment configured:"
echo "  SESI_LMHOST=$SESI_LMHOST"
echo "  VRAY_AUTH_CLIENT_FILE_PATH=$VRAY_AUTH_CLIENT_FILE_PATH"
echo "  VRAY_AUTH_CLIENT_SETTINGS=$VRAY_AUTH_CLIENT_SETTINGS"
echo ""

# Create working directory for Houdini VRay rendering
mkdir -p houdini_vray_render

echo "Creating a simple Houdini scene with a V-Ray renderer..."
docker run --rm \
  --network host \
  --ulimit stack=52428800 \
  -v "$(pwd)/houdini_vray_render:/work" \
  -v "$(pwd)/testjob-vray/houdini-vray.py:/work/houdini-vray.py" \
  -w /work \
  -e SESI_LMHOST \
  -e redshift_LICENSE \
  -e VRAY_AUTH_CLIENT_FILE_PATH \
  -e VRAY_AUTH_CLIENT_SETTINGS \
  houdini-vray \
  bash -c "source /opt/houdini/houdini_setup_bash && echo 'Testing VRay environment:' && hython -c \"import os; vray_vars = {k:v for k,v in os.environ.items() if 'vray' in k.lower() or 'vfh' in k.lower()}; print(f'VRay env vars: {vray_vars}')\" && hython /work/houdini-vray.py"

echo "Rendering the VRay scene..."
docker run --rm \
  --network host \
  --ulimit stack=52428800 \
  -v "$(pwd)/houdini_vray_render:/work" \
  -w /work \
  -e SESI_LMHOST \
  -e redshift_LICENSE \
  -e VRAY_AUTH_CLIENT_FILE_PATH \
  -e VRAY_AUTH_CLIENT_SETTINGS \
  houdini-vray \
  bash -c "source /opt/houdini/houdini_setup_bash && hrender -e -d /out/vray_renderer -f 1 1 /work/simple_scene_vray.hip -v"

echo ""
echo "Make sure to source this script or run it with 'source setup-licenses.sh'"
echo "to export the variables to your current shell session."