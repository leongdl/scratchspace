#!/bin/bash

export redshift_LICENSE=7054@localhost
export g_licenseServerRLM=localhost:7057

# Render Cinema4D scene using Docker container
sudo docker run --rm -v "$(pwd):/work" -e redshift_LICENSE="$redshift_LICENSE" -e g_licenseServerRLM="$g_licenseServerRLM" cinema4d:latest bash -c "
    echo 'Setting up Cinema4D environment for rendering...'
    source /opt/maxon/cinema4dr2025.301/bin/setup_c4d_env
    cd /opt/maxon/cinema4dr2025.301/bin
    echo 'Starting render of simple_cube_2025.c4d...'
    ./Commandline -nogui -render /work/simple_cube_2025.c4d
"