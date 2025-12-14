# VRay Standalone Docker Container

This Docker container provides a VRay standalone renderer based on Rocky Linux 9.

## Prerequisites

Before building this container, you need to obtain the VRay installer:

1. Download `vray_adv_70010_houdini20.5_gcc11_linux.zip` from Chaos Group
2. Place it in this directory (`scratchspace/vray/`)

## Building the Container

```bash
# Navigate to the vray directory
cd scratchspace/vray

# Build the container
docker build -t vray-standalone .
```

## Usage

### VRay Standalone Rendering

```bash
# Render a VRay scene file
docker run --rm -v /path/to/your/scenes:/render vray-standalone vray scene.vrscene

# Interactive mode
docker run --rm -it -v /path/to/your/scenes:/render vray-standalone bash
```

### VRay Distributed Rendering Server

```bash
# Start VRay server for distributed rendering
docker run --rm -p 20204:20204 vray-standalone vrayserver

# Start server with custom port
docker run --rm -p 30000:30000 vray-standalone vrayserver -port=30000
```

### Verification

```bash
# Verify VRay installation
docker run --rm vray-standalone verify-vray
```

## Environment Variables

The container sets up the following VRay environment variables:

- `VRAY_PATH=/opt/vray`
- `VRAY_APPSDK=/opt/vray/appsdk`
- `VRAY_OSL_PATH=/opt/vray/appsdk/bin`
- `VRAY_UI_DS_PATH=/opt/vray/ui`
- `VFH_HOME=/opt/vray/vfh_home`

## Available Commands

- `vray` - VRay standalone renderer
- `vrayserver` - VRay distributed rendering server
- `verify-vray` - Installation verification script

## File Structure

```
/opt/vray/          # VRay installation directory
├── appsdk/         # VRay SDK and binaries
├── vfh_home/       # VRay for Houdini integration
└── ui/             # VRay UI components

/render/            # Default working directory for scene files
```

## Notes

- The container runs in headless mode with `QT_QPA_PLATFORM=offscreen`
- VRay binaries are automatically added to PATH
- Python dependencies are included for VRay scripting
- Container supports both standalone rendering and distributed rendering server modes

## Troubleshooting

If VRay binaries are not found:

1. Ensure the VRay installer ZIP file is present during build
2. Check that the installer extracts to the expected directory structure
3. Run `verify-vray` to check installation status
4. Verify the installer version matches the expected filename pattern

## License

This container requires a valid VRay license. Ensure you have proper licensing before using VRay in production environments.