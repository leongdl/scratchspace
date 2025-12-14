#!/bin/bash
#
# find-missing-deps.sh
# 
# Discovers all missing shared library dependencies for VRay.
# Builds a minimal Docker image and uses ldd to find missing libs.
#
# Usage: ./find-missing-deps.sh [--no-build]
#   --no-build  Skip Docker build, assume image already exists
#
# Output: missing-libs.txt (one library per line)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="vray-minimal"
DOCKERFILE="Dockerfile.reverse-engineer"
OUTPUT_FILE="missing-libs.txt"

# Parse arguments
NO_BUILD=false
for arg in "$@"; do
    case $arg in
        --no-build)
            NO_BUILD=true
            shift
            ;;
    esac
done

echo "=== VRay Dependency Discovery ==="
echo ""

# Step 1: Build the minimal Docker image
if [ "$NO_BUILD" = false ]; then
    echo "[1/3] Building minimal Docker image..."
    cd "$SCRIPT_DIR"
    docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" . 
    echo "     Image built: $IMAGE_NAME"
else
    echo "[1/3] Skipping build (--no-build specified)"
fi
echo ""

echo "[2/3] Scanning for missing dependencies inside container..."

# Run ldd on all relevant files and collect missing libs
# Use for loops with globs instead of while read (more reliable in sh -c)
docker run --rm "$IMAGE_NAME" sh -c '
    # Scan bin directory - executables and shared libs
    for f in /opt/vray/bin/*.bin /opt/vray/bin/*.so /opt/vray/bin/*.so.*; do
        [ -f "$f" ] && ldd "$f" 2>/dev/null
    done
    
    # Scan lib directory
    for f in /opt/vray/lib/*.so /opt/vray/lib/*.so.*; do
        [ -f "$f" ] && ldd "$f" 2>/dev/null
    done
    
    # Scan Qt plugins
    for dir in /opt/vray/bin/platforms /opt/vray/bin/plugins /opt/vray/bin/imageformats /opt/vray/bin/iconengines; do
        if [ -d "$dir" ]; then
            for f in "$dir"/*.so "$dir"/*.so.*; do
                [ -f "$f" ] && ldd "$f" 2>/dev/null
            done
        fi
    done
' 2>/dev/null | grep "not found" | awk '{print $1}' | sort -u > "$SCRIPT_DIR/$OUTPUT_FILE"

# Filter out VRay's own bundled libs that reference each other
# These are false positives - they exist but ldd doesn't find them due to LD_LIBRARY_PATH
# Also filter Qt5 libs (bundled in /opt/vray/bin/) and libcuda (NVIDIA driver, not from dnf)
grep -v -E "^lib(vray|chaos|scatter|texcompress|vfb|VRay|Qt5|cuda)" "$SCRIPT_DIR/$OUTPUT_FILE" > "$SCRIPT_DIR/${OUTPUT_FILE}.tmp" || true
mv "$SCRIPT_DIR/${OUTPUT_FILE}.tmp" "$SCRIPT_DIR/$OUTPUT_FILE"

# Count results
count=$(wc -l < "$SCRIPT_DIR/$OUTPUT_FILE" | tr -d ' ')
echo "     Found $count missing libraries"
echo ""

# Step 3: Display results
echo "[3/3] Results saved to: $OUTPUT_FILE"
echo ""
echo "=== Missing Libraries ==="
if [ -s "$SCRIPT_DIR/$OUTPUT_FILE" ]; then
    cat "$SCRIPT_DIR/$OUTPUT_FILE"
else
    echo "(none found - all dependencies satisfied)"
fi
echo ""
echo "=== Next Steps ==="
echo "Run: ./install-deps.sh --dry-run"
echo "To see which packages provide these libraries."
