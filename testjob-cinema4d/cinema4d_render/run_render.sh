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
echo "$C4DEXE" -render /work/simple_cube_2025.c4d -nogui -frame 1 -oimage /work/output -oformat PNG -oresolution 800 600 2>&1 | tee /tmp/c4d.log
#RENDER_EXIT_CODE=${PIPESTATUS[0]}

echo "=== Copying Cinema4D logs to work directory ==="
#cp /tmp/c4d.log /work/c4d.log

echo ""
echo "=== Render completed at $(date) with exit code: $RENDER_EXIT_CODE ==="

echo "=== Final Working Directory Contents ==="
#ls -la /work/
#echo ""

echo "=== Script completed ==="
#exit $RENDER_EXIT_CODE
