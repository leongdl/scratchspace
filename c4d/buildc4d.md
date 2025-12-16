# Cinema4D 2025.3.3 + Redshift 2026.1.1 Docker Build

## Overview
Docker image for Cinema4D 2025.3.3 with Redshift 2026.1.1 renderer on Rocky Linux 8.

**Important:** Rocky Linux 8 is required because Cinema4D needs `libwebkit2gtk-4.0.so.37` which is only available in Rocky 8. Rocky 9 ships webkit2gtk3 with the 4.1 API which is incompatible.

## Required Files
Place these in the `c4d/` directory:
- `Cinema4D_2025_2025.3.3_Linux.sh` - Cinema4D installer
- `redshift_2026.1.1_2105803004_linux_x64.run` - Redshift installer
- `simple_cube_2025.c4d` - Test scene
- `substance_cube.zip` - Substance material test scene

## Build Command
```bash
docker build -t cinema4d:2025.3.3 -f Dockerfile.cinema4d .
```

## Run Render
```bash
# Using the helper script
./run_cinema4d.sh /rendering/substance_cube/SubstanceMaterialCube.c4d /work/output

# Or directly
docker run --rm \
    -v "$(pwd):/work" \
    -e redshift_LICENSE="7054@localhost" \
    -e g_licenseServerRLM="localhost:7057" \
    cinema4d:2025.3.3 \
    /opt/maxon/cinema4dr2025.303/bin/Commandline -nogui -render /rendering/simple_cube_2025.c4d
```

## Key Configuration

### Redshift Registration with Cinema4D
Per `/usr/redshift/redshift4c4d/install.txt`, Redshift must be registered with C4D via:

1. **Environment variable** (for command-line rendering):
   ```
   ENV g_additionalModulePath=/usr/redshift/redshift4c4d/R2025
   ```

2. **Plugin directory copy** (for automatic loading):
   ```
   cp -R /usr/redshift/redshift4c4d/R2025/* /opt/maxon/cinema4dr2025.303/bin/plugins/
   ```

The Dockerfile uses both methods.

### Environment Variables
- `REDSHIFT_COREDATAPATH=/usr/redshift` - Redshift core installation
- `REDSHIFT_LOCALDATAPATH=/root/redshift` - Logs, license, cache
- `g_additionalModulePath=/usr/redshift/redshift4c4d/R2025` - Plugin path for C4D

### License Environment Variables
- `redshift_LICENSE=7054@localhost` - RLM license server for Redshift
- `g_licenseServerRLM=localhost:7057` - Maxon RLM license server

## Installer Flags
Both installers use Makeself format:
- `--quiet` - Suppress output
- `--accept` - Accept license
- `--nox11` - No X11 (for Redshift)

## Test Scenes
The container includes:
- `/rendering/simple_cube_2025.c4d` - Basic test scene
- `/rendering/substance_cube/SubstanceMaterialCube.c4d` - Substance material test

## References
- `redshift4c4d-install.txt` - Official Redshift install instructions for C4D
- `redshift-install.md` - General Redshift Linux install docs
