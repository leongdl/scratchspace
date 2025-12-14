# VRay Dependency Discovery Plan

## Goal
Automatically discover and install all required system dependencies for VRay Standalone on Rocky Linux 9, without manually guessing packages.

## Overview

Two scripts work together:
1. **`find-missing-deps.sh`** - Discovers missing shared libraries
2. **`install-deps.sh`** - Maps libraries to packages and installs them

## Script 1: find-missing-deps.sh

### Purpose
Scan all VRay binaries and shared libraries to find missing dependencies.

### How It Works

1. **Build minimal Docker image** from `Dockerfile.reverse-engineer` (base OS + VRay, no extra packages)

2. **Inside the container:**
   - Find all executables in `/opt/vray/bin`
   - Find all `.so` files in `/opt/vray/lib`
   - Run `ldd` on each file
   - Parse for "not found" entries
   - Deduplicate results

3. **Output:** `missing-libs.txt` - one library name per line

### Usage
```bash
./find-missing-deps.sh
# Outputs: missing-libs.txt
```

### Technical Details
- Uses `ldd` to check dynamic library dependencies
- Filters out VRay's own libraries (they're bundled)
- Handles both ELF executables and shared objects
- Runs inside Docker to get accurate Rocky Linux 9 results

---

## Script 2: install-deps.sh

### Purpose
Map missing libraries to RPM packages and install them.

### How It Works

1. **Read** `missing-libs.txt`

2. **For each missing library:**
   - Run `dnf provides "*/<libname>"` to find the package
   - Parse output to extract package name
   - Handle cases where multiple packages provide the same lib

3. **Deduplicate** package list

4. **Two modes:**
   - `--dry-run`: Print packages that would be installed
   - Default: Run `dnf install -y <packages>`

### Usage
```bash
# See what would be installed
./install-deps.sh --dry-run

# Actually install
./install-deps.sh
```

### Technical Details
- Uses `dnf provides` with wildcard pattern `*/<libname>`
- Prefers base packages over `-devel` variants
- Skips libraries that are bundled with VRay
- Can be run inside the container or used to update Dockerfile

---

## Workflow Diagram

```
┌─────────────────────────────────────────────────┐
│  Dockerfile.reverse-engineer                    │
│  (Rocky Linux 9 + VRay, NO system deps)         │
└─────────────────────┬───────────────────────────┘
                      │ docker build -t vray-minimal .
                      ▼
┌─────────────────────────────────────────────────┐
│  find-missing-deps.sh                           │
│                                                 │
│  1. docker run vray-minimal                     │
│  2. find /opt/vray/bin -type f -executable      │
│  3. find /opt/vray/lib -name "*.so*"            │
│  4. ldd <each file> | grep "not found"          │
│  5. sort -u > missing-libs.txt                  │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  missing-libs.txt                               │
│                                                 │
│  libX11.so.6                                    │
│  libGL.so.1                                     │
│  libQt5Core.so.5                                │
│  ...                                            │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  install-deps.sh                                │
│                                                 │
│  1. Read missing-libs.txt                       │
│  2. dnf provides "*/libX11.so.6" → libX11       │
│  3. dnf provides "*/libGL.so.1" → mesa-libGL    │
│  4. Collect unique package names                │
│  5. --dry-run: echo packages                    │
│     or: dnf install -y <packages>               │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  Updated Dockerfile or running container        │
│  with all dependencies resolved                 │
└─────────────────────────────────────────────────┘
```

---

## Expected Output

After running both scripts, you'll have:

1. **`missing-libs.txt`** - Complete list of missing shared libraries
2. **`required-packages.txt`** - Deduplicated list of RPM packages
3. **Console output** - Dockerfile-ready dnf install command

This can then be used to update `Dockerfile.reverse-engineer` with the exact minimal set of packages needed.

---

## Actual Results (Rocky Linux 9 + VRay 7.1)

### Missing Libraries Found (29):
```
libGL.so.1, libGLU.so.1, libICE.so.6, libSM.so.6, libX11-xcb.so.1, libX11.so.6,
libXext.so.6, libXinerama.so.1, libXxf86vm.so.1, libdbus-1.so.3, libfontconfig.so.1,
libfreetype.so.6, libxcb-*.so.*, libxkbcommon*.so.*
```

### Required Packages (20):
```
dbus-libs fontconfig freetype libICE libSM libX11 libX11-xcb libXext libXinerama
libXxf86vm libglvnd-glx libxcb libxkbcommon libxkbcommon-x11 mesa-libGLU
xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm
```

### Dockerfile Command:
```dockerfile
RUN dnf install -y dbus-libs fontconfig freetype libICE libSM libX11 libX11-xcb \
    libXext libXinerama libXxf86vm libglvnd-glx libxcb libxkbcommon libxkbcommon-x11 \
    mesa-libGLU xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm
```

---

## Edge Cases Handled

- **Libraries provided by multiple packages**: Prefers non-devel, base packages
- **Libraries not in standard repos**: Reports them for manual resolution
- **VRay's bundled libraries**: Excluded from "missing" list
- **Recursive dependencies**: `ldd` naturally handles these
- **Architecture-specific libs**: Uses Rocky Linux 9 x86_64 context

---

## Files

| File | Purpose |
|------|---------|
| `Dockerfile.reverse-engineer` | Minimal Dockerfile (base + VRay only) |
| `find-missing-deps.sh` | Script 1: Find missing libraries |
| `install-deps.sh` | Script 2: Map libs to packages and install |
| `missing-libs.txt` | Output: List of missing .so files |
| `dependency-discovery-plan.md` | This document |
