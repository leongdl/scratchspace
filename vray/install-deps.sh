#!/bin/bash
#
# install-deps.sh
#
# Maps missing shared libraries to RPM packages using dnf provides.
# Runs dnf provides inside the Rocky Linux container for accurate results.
#
# Usage: 
#   ./install-deps.sh --dry-run     # Show what would be installed
#   ./install-deps.sh --dockerfile  # Output dnf install command for Dockerfile
#
# Input: missing-libs.txt (from find-missing-deps.sh)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="$SCRIPT_DIR/missing-libs.txt"
PACKAGES_FILE="$SCRIPT_DIR/required-packages.txt"
IMAGE_NAME="vray-minimal"

# Parse arguments
DRY_RUN=false
DOCKERFILE_MODE=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --dockerfile)
            DOCKERFILE_MODE=true
            ;;
    esac
done

echo "=== VRay Dependency Resolver ==="
echo ""

# Check input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: $INPUT_FILE not found."
    echo "Run ./find-missing-deps.sh first."
    exit 1
fi

# Check if input file is empty
if [ ! -s "$INPUT_FILE" ]; then
    echo "No missing libraries found in $INPUT_FILE"
    echo "All dependencies appear to be satisfied."
    exit 0
fi

echo "[1/3] Reading missing libraries from: $INPUT_FILE"
lib_count=$(wc -l < "$INPUT_FILE" | tr -d ' ')
echo "     Found $lib_count libraries to resolve"
echo ""

echo "[2/3] Resolving libraries to packages (inside Rocky Linux container)..."
echo ""

# Create resolver script to run inside container
cat > "$SCRIPT_DIR/resolver.sh" << 'RESOLVER_EOF'
#!/bin/bash
# Runs inside container to resolve libs to packages

while IFS= read -r lib; do
    [ -z "$lib" ] && continue
    
    # Use dnf provides to find the package (suppress all stderr and progress)
    result=$(dnf provides "*/$lib" -q 2>/dev/null | grep -E "^[a-zA-Z0-9].*:" | head -1 || true)
    
    if [ -n "$result" ]; then
        # Extract package name - remove version-release.arch and epoch
        pkg_full=$(echo "$result" | awk -F' : ' '{print $1}')
        # Remove epoch (e.g., "1:"), architecture (.x86_64, .i686), and version-release
        pkg_name=$(echo "$pkg_full" | sed 's/^[0-9]*://' | sed -E 's/\.(x86_64|i686|noarch)$//' | sed -E 's/-[0-9]+[.:][0-9].*$//')
        echo "$lib|$pkg_name"
    else
        echo "$lib|NOT_FOUND"
    fi
done
RESOLVER_EOF

chmod +x "$SCRIPT_DIR/resolver.sh"

# Run resolver inside container
> "$PACKAGES_FILE"
not_found_libs=""

docker run --rm -i \
    -v "$SCRIPT_DIR/resolver.sh:/resolver.sh:ro" \
    "$IMAGE_NAME" /bin/bash /resolver.sh < "$INPUT_FILE" | while IFS='|' read -r lib pkg; do
    printf "  %-30s -> %s\n" "$lib" "$pkg"
    if [ "$pkg" != "NOT_FOUND" ]; then
        echo "$pkg" >> "$PACKAGES_FILE"
    else
        echo "$lib" >> "$SCRIPT_DIR/not-found-libs.txt"
    fi
done

echo ""

# Deduplicate packages
if [ -f "$PACKAGES_FILE" ]; then
    sort -u "$PACKAGES_FILE" -o "$PACKAGES_FILE"
    package_count=$(wc -l < "$PACKAGES_FILE" | tr -d ' ')
else
    package_count=0
fi

echo "[3/3] Summary"
echo ""
echo "Unique packages needed: $package_count"
echo ""

if [ -f "$SCRIPT_DIR/not-found-libs.txt" ] && [ -s "$SCRIPT_DIR/not-found-libs.txt" ]; then
    echo "WARNING: The following libraries were not found in repos:"
    cat "$SCRIPT_DIR/not-found-libs.txt" | while read lib; do
        echo "  - $lib"
    done
    echo ""
    echo "These may need EPEL or manual resolution."
    echo ""
    rm -f "$SCRIPT_DIR/not-found-libs.txt"
fi

echo "=== Packages to Install ==="
if [ -s "$PACKAGES_FILE" ]; then
    cat "$PACKAGES_FILE"
else
    echo "(none)"
fi
echo ""

echo "Package list saved to: $PACKAGES_FILE"
echo ""

if [ "$DOCKERFILE_MODE" = true ]; then
    echo "=== Dockerfile Command ==="
    pkg_line=$(cat "$PACKAGES_FILE" | tr '\n' ' ' | sed 's/ $//')
    echo "RUN dnf install -y $pkg_line"
    echo ""
elif [ "$DRY_RUN" = true ]; then
    echo "=== Dry Run Mode ==="
    pkg_line=$(cat "$PACKAGES_FILE" | tr '\n' ' ' | sed 's/ $//')
    echo "Would run: dnf install -y $pkg_line"
    echo ""
    echo "To generate Dockerfile command: ./install-deps.sh --dockerfile"
fi

# Cleanup
rm -f "$SCRIPT_DIR/resolver.sh"
