#!/bin/bash

# Start Nuke Docker container with proper environment setup
sudo docker run -it --rm --network host --ulimit stack=52428800 nuke16:latest bash -c "
    echo 'Setting up Nuke environment...'
    export foundry_LICENSE=4101@localhost
    cd /opt/nuke/Nuke16.0v1
    echo \"Nuke environment ready. Current directory: \$(pwd)\"
    echo 'To Render: Nuke16.0 -t -x -F 1 --var \"output_path:/render/out\" /render/SimpleNuke-16.0.nk'
    mkdir -p /root/test-output
    exec bash
"