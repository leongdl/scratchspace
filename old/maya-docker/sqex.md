# Maya 2025 + Redshift + Ornatrix + SpeedTree Docker Container

## Overview
Successfully built a complete 3D production Docker container with Maya 2025, Redshift rendering, Ornatrix hair/fur simulation, and SpeedTree vegetation modeling.

## Container: `maya-ornatrix`

### Software Stack
- **Maya 2025**: Fully functional 3D software
- **Redshift 2025.5.0**: GPU rendering engine with Maya integration
- **Ornatrix Maya 2025 v5.1.2.36369**: Hair/fur simulation plugin (Demo version)
- **SpeedTree Modeler v10.0.1**: Vegetation modeling software

### Key Locations
```
/usr/autodesk/maya/                           # Maya 2025
/usr/redshift/redshift4maya                   # Redshift
/usr/autodesk/modules/maya/2025/OrnatrixMaya2025  # Ornatrix
/opt/SpeedTree/SpeedTree_Modeler_v10.0.1/    # SpeedTree
```

### Environment Variables
```bash
MAYA_LOCATION=/usr/autodesk/maya/
REDSHIFT_COREDATAPATH=/usr/redshift
SPEEDTREE_HOME=/opt/SpeedTree/SpeedTree_Modeler_v10.0.1
```

### Verification Commands
```bash
# Maya
maya -batch -command "about -version"

# Ornatrix
maya -batch -command "loadPlugin Ornatrix; pluginInfo -query -version Ornatrix"

# SpeedTree (with xcb backend)
export QT_QPA_PLATFORM=xcb
/opt/SpeedTree/SpeedTree_Modeler_v10.0.1/startSpeedTreeModeler.sh
```

### Docker Usage
```bash
# Interactive shell
docker run -it --rm maya-ornatrix /bin/bash

# Run SpeedTree with xcb
docker run -it --rm -e QT_QPA_PLATFORM=xcb maya-ornatrix /opt/SpeedTree/SpeedTree_Modeler_v10.0.1/startSpeedTreeModeler.sh
```

### Build Process
1. Base: mottosso/mayabase-rocky8:2023
2. Maya 2025 installation via wget
3. Redshift installation with module configuration
4. Ornatrix Maya 2025 installation (local file)
5. SpeedTree extraction and silent installation
6. XCB dependencies for GUI support

### Status: ✅ All software verified and functional
- Maya 2025: Working
- Redshift: Configured for Maya 2025
- Ornatrix: Plugin loads successfully, all nodes available
- SpeedTree: Installed with xcb backend support

### Qt Platform Options
- `QT_QPA_PLATFORM=xcb` - X11/xcb backend
- `QT_QPA_PLATFORM=offscreen` - Headless rendering
- `QT_QPA_PLATFORM=vnc` - VNC display
- `QT_QPA_PLATFORM=minimal` - Minimal testing
#
# Learning Software Installation Process

### How to Discover Installation Methods

#### 1. Ornatrix Installation Discovery
```bash
# Check installer help options
./Ornatrix_Maya_2025_Demonstration_5.1.2.36369.run --help

# Output showed Makeself installer with options:
# --quiet    : Silent installation
# --nox11    : No X11 GUI required
# --info     : Show embedded info
# --list     : List archive contents
```

#### 2. SpeedTree Installation Discovery
```bash
# Extract and examine installation files
tar -xzf SpeedTree_Modeler_v10.0.1_Linux.tar.gz
cd SpeedTree_Modeler_v10.0.1_Linux/SpeedTree_Modeler_v10.0.1/

# Read installation instructions
cat INSTALL.txt

# Examine installation script
cat installSpeedTreeModeler.sh
```

**Key findings from SpeedTree script:**
- Silent install option: `./installSpeedTreeModeler.sh -s`
- Extracts `data` file using `tar -zxf data`
- Makes startup script executable: `chmod u+x startSpeedTreeModeler.sh`
- Requires xcb dependencies for GUI

#### 3. General Installation Discovery Process
1. **Check for help flags**: `--help`, `-h`, `--info`
2. **Look for documentation**: `README`, `INSTALL.txt`, `*.md` files
3. **Examine scripts**: Read shell scripts to understand what they do
4. **Test extraction**: For archives, extract and explore contents
5. **Check dependencies**: Look for library requirements in docs/scripts
6. **Find silent options**: Look for unattended installation flags

#### 4. Docker Integration Strategy
- Use silent/quiet installation flags for automated builds
- Install dependencies before running installers
- Copy files to appropriate system locations
- Set environment variables for runtime
- Test functionality after installation

This approach of examining help files and installation scripts before implementation ensures successful Docker integration and understanding of software requirements.