Before you can use Redshift in Houdini, you have to tell Houdini where the Redshift plugins are located on your system. The location of the Houdini plugins must be established in one of two ways, editing a houdini.env file or creating a Houdini .json package file. This must be done for each version of Houdini you are using.

After installation, Redshift and the Houdini plugin will be installed in the /usr/redshift  default folder along with your log files, license file (if using a node-locked license), and the Redshift preferences..

The Houdini plugin files are located in the main Redshift installation folder:

Houdini: /usr/redshift/redshift4houdini/XX.X
 

Houdini .env configuration
Each user’s home Houdini directory can contain a  houdini.env file you can use to specify environment variables. The  houdini.env  file on Linux is located at  ~/houdiniX.X/houdini.env (for example: ~/houdini20.0/houdini.env)

It is also possible to set this as a system environment variables so not every user needs to maintain their own houdini.env file.

Edit your  houdini.env  file to include the following lines:

HOUDINI_DSO_ERROR = 2
PATH = "/usr/redshift/bin:$PATH"
HOUDINI_PATH = "/usr/redshift/redshift4houdini/20.0.506;&"

OCIO Support & Warnings

If you want OCIO support in Solaris, Mplay, or to avoid OCIO warnings in Houdini 20, you should force Houdini to use Redshift's default OCIO config by adding the following line to your Houdini .env configuration:

OCIO = "/usr/redshift/data/OCIO/config.ocio"

Note: This line should be added to the .env config even if you configure Redshift using a Houdini package

If you switch to the Redshift OCIO config and load a scene you already started with the Houdini OCIO config you may need to update the camera parameters so it recognizes the OCIO change. This can be accomplished by selecting the cameras in your scene and pressing the "CamParms" button highlighted in the image below. Or you can automatically update all cameras in the scene by using the "Redshift_cameraSpareParameters" command in the Houdini Textport.


 

Houdini package configuration
A Houdini package is a .json file that can be created and used to configure Redshift for Houdini instead of editing a Houdini .env file. It is generally easier to manage and maintain since they can be separated from other plugin configurations unlike in a .env file where multiple plugins share the same file. For more information, please see the Houdini Packages help page.

Create a Houdini package for Redshift that contains the following:

{​
"env":[
{​"RS_PLUGIN_VERSION" : "${​HOUDINI_VERSION}​"}​,
{​"REDSHIFT_COREDATAPATH": "/usr/redshift"}​,
{​"HOUDINI_PATH": "${​REDSHIFT_COREDATAPATH}​/redshift4houdini/${​RS_PLUGIN_VERSION}​"}​,
{​"PATH": "${​REDSHIFT_COREDATAPATH}​/bin"}​,
]
}
---


## Docker Container Build Instructions

### Building Houdini with Redshift Docker Container

This section documents how the Dockerfile.houdini-vray was modified to include Redshift installation and integration.

### Prerequisites

Required installation files:
- `houdini-20.5.613-linux_x86_64_gcc11.2.tar.gz` - Houdini installer
- `vray_adv_70010_houdini20.5_gcc11_linux.zip` - VRay for Houdini plugin
- `redshift_v3.5.25_linux.tar.gz` - Redshift installer

### Docker Build Process

#### 1. Base System Setup
- Uses Rocky Linux 9 as base image
- Installs system dependencies and libraries required for Houdini, VRay, and Redshift
- Sets up proper locale and environment variables

#### 2. Installation File Extraction
```dockerfile
# Copy all required installers
COPY houdini-20.5.613-linux_x86_64_gcc11.2.tar.gz /install/
COPY vray_adv_70010_houdini20.5_gcc11_linux.zip /install/
COPY redshift_v3.5.25_linux.tar.gz /install/

# Extract each installer
RUN unzip /install/vray_adv_70010_houdini20.5_gcc11_linux.zip -d /install/houdini_vray
RUN tar -xzf /install/houdini-20.5.613-linux_x86_64_gcc11.2.tar.gz -C /install/houdini
RUN tar -xzf /install/redshift_v3.5.25_linux.tar.gz -C /install/
```

#### 3. Houdini Installation
- Installs Houdini 20.5.613 to `/opt/houdini`
- Configures environment variables (HFS, HB, HDSO, etc.)
- Creates basic Houdini launcher script

#### 4. VRay Installation
- Installs VRay to `/opt/vray`
- Creates VRay launcher scripts
- Sets up VRay-Houdini integration

#### 5. Redshift Installation and Configuration
```dockerfile
# Install Redshift to /usr/redshift
RUN mkdir -p /usr/redshift && \
    cp -r /install/redshift_v3.5.25_linux/* /usr/redshift/ || true

# Create Houdini environment configuration for Redshift
RUN mkdir -p /opt/houdini/houdini/config && \
    echo 'HOUDINI_DSO_ERROR = 2' > /opt/houdini/houdini/config/houdini.env && \
    echo 'PATH = "/usr/redshift/bin:$PATH"' >> /opt/houdini/houdini/config/houdini.env && \
    echo 'HOUDINI_PATH = "/usr/redshift/redshift4houdini/20.5.613;&"' >> /opt/houdini/houdini/config/houdini.env && \
    echo 'OCIO = "/usr/redshift/data/OCIO/config.ocio"' >> /opt/houdini/houdini/config/houdini.env
```

### Launcher Scripts Created

#### 1. `houdini-redshift` - Redshift Only
- Sources Houdini environment
- Sets up Redshift-specific environment variables
- Configures plugin paths for Redshift integration

#### 2. `houdini-vray-redshift` - Combined Integration
- Sources Houdini environment
- Sets up both VRay and Redshift environments
- Combines plugin paths for both renderers
- Allows switching between renderers in the same session

### Environment Variables Set

**Redshift-specific variables:**
- `HOUDINI_DSO_ERROR=2` - Enable DSO error reporting
- `PATH="/usr/redshift/bin:$PATH"` - Add Redshift binaries to PATH
- `HOUDINI_PATH="/usr/redshift/redshift4houdini/20.5.613:$HOUDINI_PATH"` - Plugin discovery
- `OCIO="/usr/redshift/data/OCIO/config.ocio"` - Color management
- `REDSHIFT_LOCALDATAPATH=~/redshift` - Local data storage

### Build Command

```bash
docker build -f Dockerfile.houdini-vray -t houdini-vray-redshift .
```

### Available Rendering Commands

After building, the container provides these commands:
- `houdini` - Basic Houdini renderer
- `vray` - VRay standalone renderer
- `houdini-vray` - Houdini with VRay integration
- `houdini-redshift` - Houdini with Redshift integration
- `houdini-vray-redshift` - Houdini with both VRay and Redshift

### Usage Examples

```bash
# Run container with Redshift rendering
docker run -it --rm houdini-vray-redshift houdini-redshift scene.hip

# Run container with both VRay and Redshift available
docker run -it --rm houdini-vray-redshift houdini-vray-redshift scene.hip

# Interactive container access
docker run -it --rm houdini-vray-redshift bash
```

### File Structure in Container

```
/usr/redshift/                    # Main Redshift installation
├── bin/                          # Redshift binaries
├── redshift4houdini/            # Houdini plugins
│   └── 20.5.613/               # Version-specific plugins
├── data/                        # Redshift data files
│   └── OCIO/                   # Color management configs
└── Licenses/                    # License files

/opt/houdini/                    # Houdini installation
├── bin/                         # Houdini binaries
├── houdini/config/             # Configuration files
│   └── houdini.env            # Environment setup
└── ...

/opt/vray/                       # VRay installation
└── vrayplugins/                # VRay plugins for Houdini
```

### Notes

- The container is configured for headless rendering with `QT_QPA_PLATFORM=offscreen`
- Stack size warnings can be ignored or set at container runtime with `--ulimit`
- Redshift local data directory is created automatically at runtime
- All installation files are cleaned up after installation to reduce image size
---


## Updated Docker Container Build Instructions (Redshift 2025.5.0)

### Building Houdini with Redshift 2025.5.0 Docker Container

This section documents the updated Dockerfile.houdini-vray configuration for Redshift 2025.5.0 installation.

### Prerequisites

Updated required installation files:
- `houdini-20.5.613-linux_x86_64_gcc11.2.tar.gz` - Houdini installer
- `vray_adv_70010_houdini20.5_gcc11_linux.zip` - VRay for Houdini plugin
- `redshift_2025.5.0_1853528846_linux_x64.run` - **Updated Redshift 2025.5.0 installer**

### Key Changes for Redshift 2025.5.0

#### 1. Installation Method Update
```dockerfile
# Copy the new Redshift 2025.5.0 installer
COPY redshift_2025.5.0_1853528846_linux_x64.run /install/

# Make installer executable and run silent installation
RUN chmod +x /install/redshift_2025.5.0_1853528846_linux_x64.run
RUN /install/redshift_2025.5.0_1853528846_linux_x64.run --mode unattended --prefix /usr/redshift
```

#### 2. Updated Plugin Path Configuration
The plugin path has been updated to use the more flexible versioning approach:

**Previous (3.5.25):**
```
HOUDINI_PATH = "/usr/redshift/redshift4houdini/20.5.613;&"
```

**Updated (2025.5.0):**
```
HOUDINI_PATH = "/usr/redshift/redshift4houdini/20.5;&"
```

#### 3. Enhanced Environment Configuration
Added `REDSHIFT_COREDATAPATH` environment variable for better compatibility:

```dockerfile
# Enhanced houdini.env configuration
RUN mkdir -p /opt/houdini/houdini/config && \
    echo 'HOUDINI_DSO_ERROR = 2' > /opt/houdini/houdini/config/houdini.env && \
    echo 'PATH = "/usr/redshift/bin:$PATH"' >> /opt/houdini/houdini/config/houdini.env && \
    echo 'HOUDINI_PATH = "/usr/redshift/redshift4houdini/20.5;&"' >> /opt/houdini/houdini/config/houdini.env && \
    echo 'OCIO = "/usr/redshift/data/OCIO/config.ocio"' >> /opt/houdini/houdini/config/houdini.env && \
    echo 'REDSHIFT_COREDATAPATH = "/usr/redshift"' >> /opt/houdini/houdini/config/houdini.env
```

#### 4. Houdini Package Configuration
Added a modern Houdini package configuration as an alternative to .env files:

```dockerfile
# Create Houdini package configuration for Redshift
RUN mkdir -p /opt/houdini/packages && \
    echo '{\
    "env":[\
        {"RS_PLUGIN_VERSION" : "${HOUDINI_VERSION}"},\
        {"REDSHIFT_COREDATAPATH": "/usr/redshift"},\
        {"HOUDINI_PATH": "${REDSHIFT_COREDATAPATH}/redshift4houdini/20.5"},\
        {"PATH": "${REDSHIFT_COREDATAPATH}/bin"},\
        {"OCIO": "${REDSHIFT_COREDATAPATH}/data/OCIO/config.ocio"}\
    ]\
}' > /opt/houdini/packages/redshift.json
```

#### 5. Updated Launcher Scripts
All launcher scripts now include the `REDSHIFT_COREDATAPATH` environment variable:

```bash
# Setup Redshift environment
export HOUDINI_DSO_ERROR=2
export PATH="/usr/redshift/bin:$PATH"
export HOUDINI_PATH="/usr/redshift/redshift4houdini/20.5:$HOUDINI_PATH"
export OCIO="/usr/redshift/data/OCIO/config.ocio"
export REDSHIFT_COREDATAPATH="/usr/redshift"
export REDSHIFT_LOCALDATAPATH=~/redshift
```

### Build Command

```bash
docker build -f Dockerfile.houdini-vray -t houdini-vray-redshift:2025.5.0 .
```

### Verification

After building, verify the installation:

```bash
# Test Redshift integration
docker run -it --rm houdini-vray-redshift:2025.5.0 houdini-redshift --version

# Check plugin paths
docker run -it --rm houdini-vray-redshift:2025.5.0 bash -c "source /opt/houdini/houdini_setup_bash && echo \$HOUDINI_PATH"

# Verify Redshift installation
docker run -it --rm houdini-vray-redshift:2025.5.0 ls -la /usr/redshift/
```

### AWS Deadline Cloud Integration

The container is fully compatible with the existing `testjob-redshift/template.yaml` which uses:

```bash
houdini-redshift -e -d /out/redshift_renderer -f 1 1 /render/houdini-redshift.hip -v
```

### Compatibility Notes

- **Redshift 2025.5.0** provides improved performance and stability over 3.5.25
- **Plugin path flexibility** - Using `20.5` instead of `20.5.613` allows for better version compatibility
- **Dual configuration** - Both .env and package configurations ensure maximum compatibility
- **Enhanced OCIO support** - Proper color management configuration prevents warnings
- **License compatibility** - Supports both node-locked and floating licenses

### Troubleshooting

If you encounter issues:

1. **Plugin not found**: Check that `/usr/redshift/redshift4houdini/20.5/` exists in the container
2. **License errors**: Ensure license environment variables are properly passed through
3. **OCIO warnings**: Verify that `/usr/redshift/data/OCIO/config.ocio` exists
4. **Rendering failures**: Check that `REDSHIFT_LOCALDATAPATH` directory is writable

### File Structure in Updated Container

```
/usr/redshift/                           # Main Redshift 2025.5.0 installation
├── bin/                                 # Redshift binaries
├── redshift4houdini/                   # Houdini plugins
│   └── 20.5/                          # Version-flexible plugin directory
├── data/                               # Redshift data files
│   └── OCIO/                          # Color management configs
│       └── config.ocio                # Default OCIO configuration
└── Licenses/                           # License files

/opt/houdini/                           # Houdini installation
├── bin/                                # Houdini binaries
├── houdini/config/                     # Configuration files
│   └── houdini.env                    # Environment setup
└── packages/                           # Package configurations
    └── redshift.json                  # Redshift package config
```
---

#
# Troubleshooting Guide - Common Issues and Solutions

### Issue 1: Script Execution Errors

**Problem**: `exec /usr/local/bin/houdini-redshift: no such file or directory`

**Root Cause**: Launcher scripts created with `echo` had literal `\n` characters instead of actual newlines.

**Solution**: Use `printf` instead of `echo` for multi-line script creation:
```dockerfile
# Wrong - creates literal \n characters
RUN echo '#!/bin/bash\n\ncd /opt/houdini && source ./houdini_setup_bash\n\n...' > /usr/local/bin/houdini-redshift

# Correct - creates actual newlines
RUN printf '#!/bin/bash\n\ncd /opt/houdini && source ./houdini_setup_bash\n\n...' > /usr/local/bin/houdini-redshift
```

### Issue 2: Scene File Not Found

**Problem**: `Error: Cannot find file /render/houdini-redshift.hip`

**Root Cause**: Filename mismatch between template and actual file in container.

**Solution**: Ensure consistent naming:
- ✅ **Actual file**: `houdini_redshift.hip` (underscore)
- ✅ **Template reference**: `/render/houdini_redshift.hip`

### Issue 3: ROP Node Not Found

**Problem**: `AttributeError: 'NoneType' object has no attribute 'parm'`

**Root Cause**: `hrender` requires either `-c` (COP nodes) or `-d` (driver/ROP nodes) parameter.

**Solution**: Always specify a driver node or implement fallback logic:
```bash
# Try common ROP node names
for rop_name in "redshift1" "Redshift_ROP1" "redshift" "rs1"; do
  if houdini-redshift -d /out/$rop_name -e -f 1 1 /render/scene.hip; then
    break
  fi
done
```

### Issue 4: OCIO Configuration Errors

**Problem**: `OCIO config load error: Error could not read '/usr/redshift/data/OCIO/config.ocio'`

**Root Cause**: Case-sensitive path issue - directory is `Data` not `data`.

**Solution**: Use correct case-sensitive path:
- ❌ **Wrong**: `/usr/redshift/data/OCIO/config.ocio`
- ✅ **Correct**: `/usr/redshift/Data/OCIO/config.ocio`

### Issue 5: Redshift Plugin Loading Failures

**Problem**: `libHoudiniUI.so: cannot open shared object file: No such file or directory`

**Root Cause**: Missing Houdini DSO library path in `LD_LIBRARY_PATH`.

**Solution**: Add Houdini DSO library path to launcher scripts:
```bash
# Setup library path for Houdini DSO libraries
export LD_LIBRARY_PATH="/opt/houdini/dsolib:$LD_LIBRARY_PATH"
```

**Library Dependencies**: Redshift plugin requires access to:
- `libHoudiniUI.so`
- `libHoudiniOP1.so`, `libHoudiniOP2.so`, etc.
- `libHoudiniGEO.so`
- `libHoudiniUT.so`
- And other Houdini core libraries in `/opt/houdini/dsolib/`

---

## Complete Working Configuration

### Final Dockerfile Configuration

```dockerfile
# Create user-specific Houdini environment configuration for Redshift
RUN mkdir -p /root/houdini20.5 && \
    echo 'HOUDINI_DSO_ERROR = 2' > /root/houdini20.5/houdini.env && \
    echo 'PATH = "/usr/redshift/bin:$PATH"' >> /root/houdini20.5/houdini.env && \
    echo 'HOUDINI_PATH = "/usr/redshift/redshift4houdini/20.5.613;&"' >> /root/houdini20.5/houdini.env && \
    echo 'OCIO = "/usr/redshift/Data/OCIO/config.ocio"' >> /root/houdini20.5/houdini.env && \
    echo 'REDSHIFT_COREDATAPATH = "/usr/redshift"' >> /root/houdini20.5/houdini.env

# Create working launcher script
RUN printf '#!/bin/bash\n\
cd /opt/houdini && source ./houdini_setup_bash\n\
\n\
# Setup library path for Houdini DSO libraries\n\
export LD_LIBRARY_PATH="/opt/houdini/dsolib:$LD_LIBRARY_PATH"\n\
\n\
# Setup Redshift environment\n\
export HOUDINI_DSO_ERROR=2\n\
export PATH="/usr/redshift/bin:$PATH"\n\
export HOUDINI_PATH="/usr/redshift/redshift4houdini/20.5.613:$HOUDINI_PATH"\n\
export OCIO="/usr/redshift/Data/OCIO/config.ocio"\n\
export REDSHIFT_COREDATAPATH="/usr/redshift"\n\
export REDSHIFT_LOCALDATAPATH=~/redshift\n\
\n\
mkdir -p ~/redshift\n\
export QT_QPA_PLATFORM=offscreen\n\
\n\
/opt/houdini/bin/hrender "$@"\n' > /usr/local/bin/houdini-redshift && \
    chmod +x /usr/local/bin/houdini-redshift
```

### Critical Path Verification Checklist

Before deploying, verify these paths exist in the container:

1. **Redshift Installation**:
   - ✅ `/usr/redshift/` - Main installation directory
   - ✅ `/usr/redshift/bin/` - Redshift binaries
   - ✅ `/usr/redshift/Data/OCIO/config.ocio` - Color management config

2. **Redshift Houdini Plugin**:
   - ✅ `/usr/redshift/redshift4houdini/20.5.613/` - Plugin directory
   - ✅ `/usr/redshift/redshift4houdini/20.5.613/dso/redshift4houdini.so` - Main plugin

3. **Houdini Installation**:
   - ✅ `/opt/houdini/bin/hrender` - Houdini renderer
   - ✅ `/opt/houdini/dsolib/libHoudiniUI.so` - Required UI library
   - ✅ `/opt/houdini/houdini/config/houdini.env` - System config
   - ✅ `/root/houdini20.5/houdini.env` - User config

4. **Scene Files**:
   - ✅ `/render/houdini_redshift.hip` - Test scene file

### Environment Variables Summary

**Required for Redshift Integration**:
```bash
HOUDINI_DSO_ERROR=2                                    # Enable DSO error reporting
PATH="/usr/redshift/bin:$PATH"                        # Redshift binaries
HOUDINI_PATH="/usr/redshift/redshift4houdini/20.5.613:$HOUDINI_PATH"  # Plugin path
OCIO="/usr/redshift/Data/OCIO/config.ocio"           # Color management
REDSHIFT_COREDATAPATH="/usr/redshift"                 # Redshift data path
REDSHIFT_LOCALDATAPATH=~/redshift                     # Local cache directory
LD_LIBRARY_PATH="/opt/houdini/dsolib:$LD_LIBRARY_PATH"  # Houdini libraries
QT_QPA_PLATFORM=offscreen                            # Headless rendering
```

### AWS Deadline Cloud Template Requirements

**Command Structure**:
```bash
# Try multiple ROP node names for robustness
for rop_name in "redshift1" "Redshift_ROP1" "redshift" "rs1"; do
  if houdini-redshift -d /out/$rop_name -e -f 1 1 /render/houdini_redshift.hip -v; then
    echo "Successfully rendered with ROP node: /out/$rop_name"
    break
  fi
done
```

**License Environment Variables**:
```bash
-e SESI_LMHOST \
-e redshift_LICENSE \
-e REDSHIFT_LICENSE_SERVER \
-e REDSHIFT_LICENSE_FILE \
```

### Performance and Optimization Notes

1. **Container Size**: Final image ~26GB (includes Houdini, VRay, Redshift)
2. **Build Time**: ~2-3 minutes with proper layer caching
3. **Memory Requirements**: Minimum 8GB RAM for rendering
4. **Stack Size**: Use `--ulimit stack=52428800` for container runtime

### Version Compatibility Matrix

| Component | Version | Notes |
|-----------|---------|-------|
| Houdini | 20.5.613 | Base 3D software |
| Redshift | 2025.5.0 | GPU renderer |
| VRay | 7.0.010 | CPU/GPU renderer |
| Rocky Linux | 9 | Base OS |
| Python | 3.11 | Required by Houdini |
| Qt | 5.x | GUI libraries |

This comprehensive troubleshooting guide should help resolve common issues and provide a complete working configuration for future deployments.