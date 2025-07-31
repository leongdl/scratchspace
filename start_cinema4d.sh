#!/bin/bash

# Start Cinema4D Docker container with proper environment setup
sudo docker run -it --rm cinema4d:latest bash -c "
    echo 'Setting up Cinema4D environment...'
    source /opt/maxon/cinema4dr2025.301/bin/setup_c4d_env
    cd /opt/maxon/cinema4dr2025.301/bin
    echo \"Cinema4D environment ready. Current directory: \$(pwd)\"
    exec bash
"