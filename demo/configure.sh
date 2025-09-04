#!/bin/bash

# Houdini + RenderMan Docker Configuration Script
# This script automatically detects software versions from installation files
# and updates the Dockerfile and run script accordingly

set -e

echo "=== Houdini + RenderMan Docker Configuration ==="
echo ""

# Function to extract version from filename
extract_houdini_version() {
    local file="$1"
    if [[ $file =~ houdini-([0-9]+\.[0-9]+\.[0-9]+)-linux ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

extract_renderman_version() {
    local file="$1"
    if [[ $file =~ RenderMan.*-([0-9]+\.[0-9]+)_ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Check for installation files
echo "Scanning for installation files..."

# Find Houdini tar.gz files
HOUDINI_FILES=($(ls houdini-*.tar.gz 2>/dev/null || true))
if [ ${#HOUDINI_FILES[@]} -eq 0 ]; then
    echo "❌ No Houdini installation files found (houdini-*.tar.gz)"
    echo "Please place Houdini installation file in this directory"
    exit 1
fi

# Find RenderMan files
RENDERMAN_FOR_HOUDINI_FILES=($(ls RenderManForHoudini-*.rpm 2>/dev/null || true))
RENDERMAN_PROSERVER_FILES=($(ls RenderManProServer-*.rpm 2>/dev/null || true))

if [ ${#RENDERMAN_FOR_HOUDINI_FILES[@]} -eq 0 ]; then
    echo "❌ No RenderMan for Houdini files found (RenderManForHoudini-*.rpm)"
    exit 1
fi

if [ ${#RENDERMAN_PROSERVER_FILES[@]} -eq 0 ]; then
    echo "❌ No RenderMan ProServer files found (RenderManProServer-*.rpm)"
    exit 1
fi

# Display found files and let user select
echo ""
echo "Found installation files:"
echo ""

echo "Houdini installations:"
for i in "${!HOUDINI_FILES[@]}"; do
    version=$(extract_houdini_version "${HOUDINI_FILES[$i]}")
    echo "  [$((i+1))] ${HOUDINI_FILES[$i]} (Version: $version)"
done

echo ""
echo "RenderMan for Houdini installations:"
for i in "${!RENDERMAN_FOR_HOUDINI_FILES[@]}"; do
    version=$(extract_renderman_version "${RENDERMAN_FOR_HOUDINI_FILES[$i]}")
    echo "  [$((i+1))] ${RENDERMAN_FOR_HOUDINI_FILES[$i]} (Version: $version)"
done

echo ""
echo "RenderMan ProServer installations:"
for i in "${!RENDERMAN_PROSERVER_FILES[@]}"; do
    version=$(extract_renderman_version "${RENDERMAN_PROSERVER_FILES[$i]}")
    echo "  [$((i+1))] ${RENDERMAN_PROSERVER_FILES[$i]} (Version: $version)"
done

echo ""

# Get user selections
read -p "Select Houdini installation [1]: " houdini_choice
houdini_choice=${houdini_choice:-1}
HOUDINI_FILE="${HOUDINI_FILES[$((houdini_choice-1))]}"

read -p "Select RenderMan for Houdini [1]: " rfh_choice
rfh_choice=${rfh_choice:-1}
RFH_FILE="${RENDERMAN_FOR_HOUDINI_FILES[$((rfh_choice-1))]}"

read -p "Select RenderMan ProServer [1]: " rps_choice
rps_choice=${rps_choice:-1}
RPS_FILE="${RENDERMAN_PROSERVER_FILES[$((rps_choice-1))]}"

# Extract versions
HOUDINI_VERSION=$(extract_houdini_version "$HOUDINI_FILE")
RENDERMAN_VERSION=$(extract_renderman_version "$RFH_FILE")

if [ -z "$HOUDINI_VERSION" ] || [ -z "$RENDERMAN_VERSION" ]; then
    echo "❌ Could not extract version information from filenames"
    exit 1
fi

# Parse Houdini version components
IFS='.' read -r H_MAJOR H_MINOR H_BUILD <<< "$HOUDINI_VERSION"

echo ""
echo "Configuration Summary:"
echo "  Houdini: $HOUDINI_VERSION (Major: $H_MAJOR, Minor: $H_MINOR, Build: $H_BUILD)"
echo "  RenderMan: $RENDERMAN_VERSION"
echo "  Houdini File: $HOUDINI_FILE"
echo "  RenderMan for Houdini: $RFH_FILE"
echo "  RenderMan ProServer: $RPS_FILE"
echo ""

read -p "Proceed with configuration? [Y/n]: " confirm
confirm=${confirm:-Y}
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Configuration cancelled"
    exit 0
fi

# Backup original files
echo ""
echo "Creating backups..."
cp Dockerfile Dockerfile.backup.$(date +%Y%m%d_%H%M%S)
cp run-houdini-rdman.sh run-houdini-rdman.sh.backup.$(date +%Y%m%d_%H%M%S)

# Update Dockerfile
echo "Updating Dockerfile..."

# Update COPY commands
sed -i "s|COPY houdini-.*\.tar\.gz|COPY $HOUDINI_FILE|g" Dockerfile
sed -i "s|COPY RenderManForHoudini-.*\.rpm|COPY $RFH_FILE|g" Dockerfile
sed -i "s|COPY RenderManProServer-.*\.rpm|COPY $RPS_FILE|g" Dockerfile

# Update tar extraction path
sed -i "s|tar -xzf /install/houdini-.*\.tar\.gz|tar -xzf /install/$HOUDINI_FILE|g" Dockerfile
sed -i "s|cd /install/houdini/houdini-.*-linux_x86_64_gcc[0-9]*\.[0-9]*|cd /install/houdini/houdini-$HOUDINI_VERSION-linux_x86_64_gcc11.2|g" Dockerfile

# Update cleanup path
sed -i "s|rm -rf /install/houdini-.*\.tar\.gz|rm -rf /install/$HOUDINI_FILE|g" Dockerfile

# Update version environment variables
sed -i "s|ENV HOUDINI_MAJOR_RELEASE=.*|ENV HOUDINI_MAJOR_RELEASE=$H_MAJOR|g" Dockerfile
sed -i "s|ENV HOUDINI_MINOR_RELEASE=.*|ENV HOUDINI_MINOR_RELEASE=$H_MINOR|g" Dockerfile
sed -i "s|ENV HOUDINI_BUILD_VERSION=.*|ENV HOUDINI_BUILD_VERSION=$H_BUILD|g" Dockerfile

# Update RenderMan paths
sed -i "s|ENV RMANTREE=/opt/pixar/RenderManProServer-.*|ENV RMANTREE=/opt/pixar/RenderManProServer-$RENDERMAN_VERSION|g" Dockerfile
sed -i "s|ENV RFHTREE=/opt/pixar/RenderManForHoudini-.*|ENV RFHTREE=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION|g" Dockerfile
sed -i "s|ENV RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-.*/3.10/.*|ENV RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION/openvdb|g" Dockerfile
sed -i "s|ENV HOUDINI_PATH=/opt/pixar/RenderManForHoudini-.*/3.10/.*:/opt/houdini|ENV HOUDINI_PATH=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION:/opt/houdini|g" Dockerfile

# Update RPM installation commands
sed -i "s|rpm -ivh /install/RenderManForHoudini-.*\.rpm|rpm -ivh /install/$RFH_FILE|g" Dockerfile
sed -i "s|rpm -ivh --verbose /install/RenderManProServer-.*\.rpm|rpm -ivh --verbose /install/$RPS_FILE|g" Dockerfile
sed -i "s|rpm -qpR /install/RenderManProServer-.*\.rpm|rpm -qpR /install/$RPS_FILE|g" Dockerfile

# Update JSON configuration paths
sed -i "s|\"RMANTREE\": \"/opt/pixar/RenderManProServer-.*\"|\"RMANTREE\": \"/opt/pixar/RenderManProServer-$RENDERMAN_VERSION\"|g" Dockerfile
sed -i "s|\"RFHTREE\": \"/opt/pixar/RenderManForHoudini-.*\"|\"RFHTREE\": \"/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION\"|g" Dockerfile
sed -i "s|\"RMAN_PROCEDURALPATH\": \"/opt/pixar/RenderManForHoudini-.*/3.10/.*/openvdb\"|\"RMAN_PROCEDURALPATH\": \"/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION/openvdb\"|g" Dockerfile
sed -i "s|\"path\": \"/opt/pixar/RenderManForHoudini-.*/3.10/.*\"|\"path\": \"/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION\"|g" Dockerfile

# Update launcher script paths
sed -i "s|export RMANTREE=/opt/pixar/RenderManProServer-.*|export RMANTREE=/opt/pixar/RenderManProServer-$RENDERMAN_VERSION|g" Dockerfile
sed -i "s|export RFHTREE=/opt/pixar/RenderManForHoudini-.*|export RFHTREE=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION|g" Dockerfile
sed -i "s|export RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-.*/3.10/.*/openvdb|export RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION/openvdb|g" Dockerfile
sed -i "s|export HOUDINI_PATH=/opt/pixar/RenderManForHoudini-.*/3.10/.*:/opt/houdini|export HOUDINI_PATH=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION:/opt/houdini|g" Dockerfile

# Update final echo message
sed -i "s|echo \"RenderMan for Houdini .* and RenderMan ProServer .* integrated\"|echo \"RenderMan for Houdini $RENDERMAN_VERSION and RenderMan ProServer $RENDERMAN_VERSION integrated\"|g" Dockerfile

# Update run script
echo "Updating run-houdini-rdman.sh..."

# Update RenderMan environment variables in run script
sed -i "s|export RMANTREE=/opt/pixar/RenderManProServer-.*|export RMANTREE=/opt/pixar/RenderManProServer-$RENDERMAN_VERSION|g" run-houdini-rdman.sh
sed -i "s|export RFHTREE=/opt/pixar/RenderManForHoudini-.*|export RFHTREE=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION|g" run-houdini-rdman.sh
sed -i "s|export RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-.*/3.10/.*/openvdb|export RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION/openvdb|g" run-houdini-rdman.sh
sed -i "s|export HOUDINI_PATH=/opt/pixar/RenderManForHoudini-.*/3.10/.*:/opt/houdini:/opt/houdini|export HOUDINI_PATH=/opt/pixar/RenderManForHoudini-$RENDERMAN_VERSION/3.10/$HOUDINI_VERSION:/opt/houdini:/opt/houdini|g" run-houdini-rdman.sh

echo ""
echo "✅ Configuration complete!"
echo ""
echo "Updated files:"
echo "  - Dockerfile (backup: Dockerfile.backup.*)"
echo "  - run-houdini-rdman.sh (backup: run-houdini-rdman.sh.backup.*)"
echo ""
echo "Next steps:"
echo "  1. Build container: docker build -t houdini-rdman:latest ."
echo "  2. Test installation: ./run-houdini-rdman.sh \"prman -version\""
echo "  3. Test rendering: ./run-houdini-rdman.sh \"hrender -v -d renderman1 /workspace/RMAN_test_02.hip\""
echo ""