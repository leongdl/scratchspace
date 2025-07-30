#!/bin/bash

# License server configuration for Cinema4D rendering
# This script sets up the necessary environment variables for license servers

echo "Setting up license server environment variables..."

# Redshift license server configuration
# Points to the license server on localhost:5054
export redshift_LICENSE=5054@localhost

# Set correct plugin paths for Cinema4D
export C4D_PLUGINS_DIR=/opt/maxon/cinema4dr2025.301/bin/plugins

echo "License environment configured:"
echo "  redshift_LICENSE=$redshift_LICENSE"
echo "  C4D_PLUGINS_DIR=$C4D_PLUGINS_DIR"
echo ""

# Change to the testjob-cinema4d directory
cd "$(dirname "$0")"

# Create working directory for Cinema4D rendering
mkdir -p cinema4d_render

# Copy the Cinema4D scene file to the render directory
echo "Copying Cinema4D scene file..."
cp simple_cube_2025.c4d cinema4d_render/

echo "Creating run script and rendering the Cinema4D scene (frame 1 only)..."

# Create the run script that will be executed inside the container
cat > cinema4d_render/run_render.sh << 'EOF'
#!/bin/bash

# Log everything to a file
exec > /work/render.log 2>&1

echo "=== Cinema4D Render Script Started at $(date) ==="
echo ""

# Cinema4D Environment Setup
C4DEXE="/opt/maxon/cinema4dr2025.301/bin/Commandline"
C4DBASE=$(dirname "${C4DEXE}")
C4DVERSION="2025.3"

echo "=== Setting up Cinema4D Environment ==="
echo "C4DEXE: $C4DEXE"
echo "C4DBASE: $C4DBASE"
echo "C4DVERSION: $C4DVERSION"
echo ""

echo "Manually setting LD_LIBRARY_PATH, PATH, and PYTHONPATH to Cinema4D components"
LD_LIBRARY_PATH_=${LD_LIBRARY_PATH-""}
export LD_LIBRARY_PATH="${C4DBASE}/resource/modules/python/libs/*linux64*/lib64:${C4DBASE}/resource/modules/embree.module/libs/linux64:$LD_LIBRARY_PATH_"
export PATH="${C4DBASE}:$PATH"
PYTHONPATH_=${PYTHONPATH-""}
export PYTHONPATH="${C4DBASE}/resource/modules/python/libs/*linux64*/lib/python*/lib-dynload:${C4DBASE}/resource/modules/python/libs/*linux64*/lib64/python*:$PYTHONPATH_"

if [ -f "${C4DBASE}/setup_c4d_env" ]; then
    cd $C4DBASE
    echo "Sourcing setup_c4d_env from ${C4DBASE}/setup_c4d_env"
    source "${C4DBASE}/setup_c4d_env"
    
    # Hacky patch to allow for libwebkit2gtk to load if C4D provides a really old version of libstdc++.so
    if (( $(echo "2024.4 > $C4DVERSION" |bc -l) )); then
        echo "Cinema 4D version $C4DVERSION is less than 2024.4."
        echo "  Patching in libstdc++.so from system"
        export LD_LIBRARY_PATH="/usr/lib64:$LD_LIBRARY_PATH"
    fi
else
    echo "setup_c4d_env not found in ${C4DBASE}"
fi

# Return to work directory
cd /work

echo "=== Environment Variables Inside Container ==="
echo "redshift_LICENSE=$redshift_LICENSE"
echo "C4D_PLUGINS_DIR=$C4D_PLUGINS_DIR"
echo "g_additionalModulePath=$g_additionalModulePath"
echo "PATH=$PATH"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "PYTHONPATH=$PYTHONPATH"
echo "=============================================="
echo ""

echo "=== All Environment Variables with Cinema4D/Redshift/Maxon ==="
set | grep -E '(redshift|C4D|g_additional|MAXON|cinema4d)' || echo 'No matching environment variables found'
echo ""

echo "=== Working Directory Contents ==="
ls -la /work/
echo ""

echo "=== Cinema4D Installation Check ==="
ls -la /opt/maxon/cinema4dr2025.301/bin/
echo ""

echo "=== Plugin Directory Check ==="
ls -la /opt/maxon/cinema4dr2025.301/bin/plugins/
echo ""

echo "=== Starting Cinema4D render at $(date) ==="
"$C4DEXE" -render /work/simple_cube_2025.c4d -nogui -frame 1 -oimage /work/output -oformat PNG -oresolution 800 600 2>&1 | tee /tmp/c4d.log
RENDER_EXIT_CODE=${PIPESTATUS[0]}

echo "=== Copying Cinema4D logs to work directory ==="
cp /tmp/c4d.log /work/c4d.log

echo ""
echo "=== Render completed at $(date) with exit code: $RENDER_EXIT_CODE ==="

echo "=== Final Working Directory Contents ==="
ls -la /work/
echo ""

echo "=== Script completed ==="
exit $RENDER_EXIT_CODE
EOF

# Make the script executable
chmod +x cinema4d_render/run_render.sh

echo ""
echo "=== Setup Complete ==="
echo "Environment variables exported:"
echo "  redshift_LICENSE=$redshift_LICENSE"
echo "  C4D_PLUGINS_DIR=$C4D_PLUGINS_DIR"
echo ""
echo "Files prepared:"
echo "  - Scene file: cinema4d_render/simple_cube_2025.c4d"
echo "  - Render script: cinema4d_render/run_render.sh"
echo ""
echo "=== Docker Command to Run Cinema4D Render ==="
echo "Copy and paste this command to run the Cinema4D render:"
echo ""
echo "docker run --rm \\"
echo "  --network host \\"
echo "  -v \"\$(pwd)/cinema4d_render:/work\" \\"
echo "  -w /work \\"
echo "  -e redshift_LICENSE \\"
echo "  -e C4D_PLUGINS_DIR \\"
echo "  cinema4d:2025 \\"
echo "  bash /work/run_render.sh"
echo ""
echo "Or run it interactively to debug:"
echo ""
echo "docker run --rm -it \\"
echo "  --network host \\"
echo "  -v \"\$(pwd)/cinema4d_render:/work\" \\"
echo "  -w /work \\"
echo "  -e redshift_LICENSE \\"
echo "  -e C4D_PLUGINS_DIR \\"
echo "  cinema4d:2025 \\"
echo "  bash"
echo ""
echo "Then inside the container run: bash /work/run_render.sh"
echo ""
echo "Make sure to source this script with 'source test.sh' to export the environment variables."