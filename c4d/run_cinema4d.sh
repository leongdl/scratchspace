#!/bin/bash

# Cinema4D 2025.3.3 + Redshift 2026.1.1 Docker Render Script
# License Configuration:
#   redshift_LICENSE: RLM license server for Redshift (port 5054)
#   g_licenseServerRLM: Maxon RLM license server (port 5054)

#export redshift_LICENSE=5054@localhost
#export g_licenseServerRLM=localhost:5054
export redshift_LICENSE=7054@vpce-05fcc31ebc6d8f676-vpwv064w.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com
export g_licenseServerRLM=vpce-05fcc31ebc6d8f676-vpwv064w.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com:7057

export redshift_LICENSE=7054@vpce-05fcc31ebc6d8f676-vpwv064w.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com:7055@vpce-05fcc31ebc6d8f676-vpwv064w.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com
export g_licenseServerRLM=vpce-05fcc31ebc6d8f676-vpwv064w.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com:7057


# From SMF 
# redshift_LICENSE=7054@vpce-046454d9b098297c3-5mzzpf4p.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com:7055@vpce-046454d9b098297c3-5mzzpf4p.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com
# g_licenseServerRLM=vpce-046454d9b098297c3-5mzzpf4p.vpce-svc-0c4b155bc5b761304.us-west-2.vpce.amazonaws.com:7057


# Default scene to render (use container path for built-in scenes, or /work/... for mounted files)
SCENE_FILE="${1:-/rendering/simple_cube_2025.c4d}"
OUTPUT_DIR="${2:-/work/output}"

sudo docker run --rm \
    --network host \
    --ulimit stack=52428800 \
    --gpus all \
    --runtime nvidia \
    --device /dev/nvidia0 \
    --device /dev/nvidiactl \
    --device /dev/nvidia-modeset \
    --device /dev/nvidia-uvm \
    -v "$(pwd):/work" \
    -e redshift_LICENSE \
    -e g_licenseServerRLM \
    cinema4d:2025.3.3 bash -c '
        mkdir -p '"${OUTPUT_DIR}"'
        echo "Rendering: '"${SCENE_FILE}"'"
        echo "Output: '"${OUTPUT_DIR}"'"
        
        # Cinema4D Environment Setup
        C4DEXE="/opt/maxon/cinema4dr2025.303/bin/Commandline"
        C4DBASE=$(dirname "${C4DEXE}")
        
        if [ -f "${C4DBASE}/setup_c4d_env" ]; then
            cd $C4DBASE
            echo "Sourcing setup_c4d_env from ${C4DBASE}"
            source "${C4DBASE}/setup_c4d_env"
        fi
        
        cd /work
        "$C4DEXE" -nogui -render '"${SCENE_FILE}"' -oimage '"${OUTPUT_DIR}"'/frame
    '
