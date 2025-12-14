#!/bin/bash
# Scanner script - runs inside container

VRAY_BIN="/opt/vray/bin"
VRAY_LIB="/opt/vray/lib"

# Function to scan a file with ldd
scan_file() {
    local file="$1"
    ldd "$file" 2>/dev/null | grep "not found" | awk '{print $1}'
}

# Scan bin directory
if [ -d "$VRAY_BIN" ]; then
    for file in "$VRAY_BIN"/*; do
        if [ -f "$file" ]; then
            if file "$file" 2>/dev/null | grep -q "ELF"; then
                scan_file "$file"
            fi
        fi
    done
fi

# Scan lib directory  
if [ -d "$VRAY_LIB" ]; then
    find "$VRAY_LIB" -type f \( -name "*.so" -o -name "*.so.*" \) 2>/dev/null | while read -r file; do
        if file "$file" 2>/dev/null | grep -q "ELF"; then
            scan_file "$file"
        fi
    done
fi

# Scan plugins
for extra_dir in "$VRAY_BIN/plugins" "$VRAY_BIN/platforms" "$VRAY_BIN/imageformats"; do
    if [ -d "$extra_dir" ]; then
        find "$extra_dir" -type f \( -name "*.so" -o -name "*.so.*" \) 2>/dev/null | while read -r file; do
            if file "$file" 2>/dev/null | grep -q "ELF"; then
                scan_file "$file"
            fi
        done
    fi
done
