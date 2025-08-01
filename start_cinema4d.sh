#!/bin/bash

# Start Cinema4D Docker container with proper environment setup
sudo docker run -it --rm --network host --ulimit stack=52428800 cinema4d:latest bash -c "
    echo 'Setting up Cinema4D environment...'
    source /opt/maxon/cinema4dr2025.002/bin/setup_c4d_env
    cd /opt/maxon/cinema4dr2025.002/bin
    echo \"Cinema4D environment ready. Current directory: \$(pwd)\"
    exec bash
"