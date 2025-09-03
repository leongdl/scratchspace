# RenderMan ProServer Installation Guide

## Overview
RenderMan ProServer 26.1 has been integrated into the Houdini Docker container to provide complete RenderMan rendering capabilities.

## What is RenderMan ProServer?
RenderMan ProServer is Pixar's production-quality rendering engine that provides:
- The core `prman` renderer
- Texture tools (`txmake`, `ptxmake`)
- Image utilities (`tiffinfo`, `exrinfo`, etc.)
- Denoising tools (`denoise`)
- Statistics and debugging tools
- Python bindings for RenderMan

## Installation Details

### Files Installed
The ProServer RPM installs to `/opt/pixar/RenderManProServer-26.1/` with:
- `bin/` - Core rendering executables including `prman`
- `lib/` - Shared libraries and Python modules
- `include/` - C++ headers for development
- `etc/` - Configuration files and setup tools

### Environment Variables
The following environment variables are set:
- `RMANTREE=/opt/pixar/RenderManProServer-26.1` - RenderMan installation root
- `PATH` includes `$RMANTREE/bin` - Access to prman and utilities
- `LD_LIBRARY_PATH` includes `$RMANTREE/lib` - Shared library access

### Integration with Houdini
The ProServer works alongside RenderMan for Houdini:
- `RFHTREE=/opt/pixar/RenderManForHoudini-26.1` - Houdini plugin location
- `HOUDINI_PATH` includes RenderMan for Houdini paths
- Houdini package configuration links to ProServer

## Testing the Installation

### Basic Test
Run the test script to verify installation:
```bash
test-renderman
```

This will:
1. Check `prman -version` command
2. Run the confidence test from `$RMANTREE/etc/setup`
3. Verify core functionality

### Manual Testing
You can also test manually:
```bash
# Test prman directly
export RMANTREE=/opt/pixar/RenderManProServer-26.1
export PATH=$RMANTREE/bin:$PATH
prman -version

# Run confidence test
cd $RMANTREE/etc/setup
make
```

### Expected Output
The confidence test should show:
```
The images are essentially identical.
```

## Usage in Houdini
With both RenderMan for Houdini and ProServer installed:
1. Houdini can create RenderMan scenes
2. The scenes render using the ProServer `prman` engine
3. All RenderMan features are available (materials, lights, etc.)

## Troubleshooting

### License Requirements
RenderMan ProServer requires a valid license. In production:
- Set up license server configuration
- Ensure network access to license server
- Configure `$RMANTREE/etc/rendermn.ini` if needed

### Common Issues
1. **Missing libraries**: Ensure `LD_LIBRARY_PATH` includes `$RMANTREE/lib`
2. **Command not found**: Ensure `PATH` includes `$RMANTREE/bin`
3. **License errors**: Check license server connectivity

## File Structure
```
/opt/pixar/RenderManProServer-26.1/
├── bin/           # Executables (prman, txmake, etc.)
├── lib/           # Libraries and Python modules
├── include/       # Development headers
└── etc/           # Configuration and setup files
```

The ProServer provides the rendering engine while RenderMan for Houdini provides the Houdini integration layer.
#
# Dependency Resolution

### ncurses Compatibility Issue
During installation, RenderMan ProServer requires `libtinfo.so.5` which is not available by default in Rocky Linux 9. This was resolved by:

1. **Enabling the devel repository**:
   ```dockerfile
   RUN dnf install -y dnf-plugins-core && \
       dnf config-manager --set-enabled devel
   ```

2. **Installing ncurses-compat-libs**:
   ```dockerfile
   RUN dnf install -y ncurses-compat-libs
   ```

3. **Verification**:
   ```bash
   ls -la /usr/lib64/libtinfo*
   # Shows:
   # lrwxrwxrwx. 1 root root     15 Aug  5 19:20 /usr/lib64/libtinfo.so.5 -> libtinfo.so.5.9
   # -rwxr-xr-x. 1 root root 182408 Aug  5 19:20 /usr/lib64/libtinfo.so.5.9
   ```

### Container Build Status
The container `houdini-rdman:latest` now includes:
- ✅ Houdini 20.0.653 installed
- ✅ RenderMan for Houdini 26.1 plugin installed  
- ✅ RenderMan ProServer 26.1 installed and working
- ✅ All required dependencies including `libtinfo.so.5`

### Verification Commands
After successful build, prman works correctly:
```bash
sudo docker run --rm houdini-rdman:latest bash -c "export RMANTREE=/opt/pixar/RenderManProServer-26.1 && export PATH=\$RMANTREE/bin:\$PATH && export LD_LIBRARY_PATH=\$RMANTREE/lib:\$LD_LIBRARY_PATH && prman -version"
```

Output:
```
Pixar PhotoRealistic RenderMan 26.1
  linked Sun Apr 21 20:10:23 2024 PDT @2324837
  build linuxRHEL7_x86-64_gcc93icx232_external_release
  copyright (c) 1988-2024 Pixar.
```

### Docker Commands Reference
- **Build container**: `sudo docker build -t houdini-rdman:latest -f Dockerfile.houdini-rdman .`
- **Run container**: `./run-houdini-rdman.sh`
- **Test RenderMan**: `./run-houdini-rdman.sh "test-renderman"`
- **Check prman**: `./run-houdini-rdman.sh "prman -version"`

The run script (`run-houdini-rdman.sh`) is correctly configured to use `houdini-rdman:latest` and automatically sets up all RenderMan environment variables.