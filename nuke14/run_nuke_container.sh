#!/bin/bash

# Simple shell script to run the Nuke Docker container
# This script runs the container with Foundry license environment only

# Clean the output directory for a fresh test
echo "Cleaning docker_out directory for fresh test..."
sudo rm -rf docker_out/*

# Export the Foundry license environment variable
export foundry_LICENSE="6101@localhost"

docker run --rm \
  --network host \
  --ulimit stack=52428800 \
  -v "$(pwd)/docker_out:/output" \
  -w /opt/nuke \
  -e foundry_LICENSE \
  nuke14:latest \
  bash -c "
    echo 'Setting up Nuke environment...'
    export FLEXLM_TIMEOUT=3000000
    
    echo 'Creating temporary render output directory...'
    mkdir -p /tmp/output
    
    echo 'Displaying license environment variables:'
    echo \"Foundry License endpoint: \$foundry_LICENSE\"
    
    echo 'Displaying Nuke environment variables:'
    echo \"Nuke path: /opt/nuke\"
    echo \"Current directory: \$(pwd)\"
    echo \"Available samples in /samples:\"
    ls -la /samples/
    echo \"Temporary render output directory: /tmp/output\"
    
    echo 'Starting Nuke render...'
    ./Nuke14.1 -t /samples/render_script.py
    
    echo 'Copying rendered files to mounted output directory...'
    mkdir -p /output
    cp -v /tmp/output/* /output/ 2>/dev/null || echo 'No files to copy or copy failed'
    
    echo 'Creating MPEG video from PNG sequence using ffmpeg...'
    cd /tmp/output
    ffmpeg -y -framerate 24 -i simple.%04d.png -c:v mpeg2video -b:v 5000k /output/motionblur_sequence.mpg
    
    echo 'Video creation completed. Files available:'
    ls -la /output/
    echo 'Render and video process completed.'
  "