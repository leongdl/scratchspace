# Nuke 14.1 + OFX Plugins Docker Container

A complete Docker setup for running Nuke 14.1v8 with KeenTools, NeatVideo, and RSMB plugins for headless rendering.

## Prerequisites

- Docker installed and running
- Valid Nuke license
- License server accessible from the container

## Quick Start

### Build the Container
```bash
docker build -t nuke14-plugins-final .
```

### Run a Test Render
```bash
./run_nuke_container.sh
```

## What's Included

### Core Application
- **Nuke 14.1v8** - Professional compositing software
- **FFmpeg** - Video encoding/decoding support
- **Rocky Linux 8** - Stable base OS

### Installed Plugins

#### 1. KeenTools 2025.2.0
- **Type:** Native Nuke Plugin (.so)
- **Format:** Native Nuke plugin (not OFX)
- **Location:** `/usr/local/NUKE/14.1/plugins/KeenTools/`
- **Main Plugin:** `/usr/local/NUKE/14.1/plugins/KeenTools/plugin_libs/KeenTools.so`
- **Status:** ✅ Registered (Nuke-specific plugin directory)
- **Features:** Face tracking, GeoTracker, FaceBuilder
- **Discovery:** Automatically loaded from Nuke plugin directory

#### 2. NeatVideo 6 OFX Demo
- **Type:** OFX Plugin (.ofx)
- **Format:** Standard OFX bundle
- **Location:** `/usr/local/Neat Video v6 OFX/NeatVideo6.ofx.bundle/`
- **Main Plugin:** `/usr/local/Neat Video v6 OFX/NeatVideo6.ofx.bundle/Contents/Linux-x86-64/NeatVideo6.ofx`
- **Symlink:** `/usr/OFX/Plugins/NeatVideo6.ofx.bundle` → `/usr/local/Neat Video v6 OFX/NeatVideo6.ofx.bundle`
- **Status:** ✅ Registered (Standard OFX directory via symlink)
- **Features:** Noise reduction and video enhancement
- **Discovery:** Automatically loaded from `/usr/OFX/Plugins/`

#### 3. RSMB 6 OFX (ReelSmart Motion Blur)
- **Type:** OFX Plugin (.ofx) - 3 variants
- **Format:** Standard OFX bundles
- **Location:** `/usr/OFX/Plugins/RSMB6OFX/`
- **Main Plugins:**
  - **Main RSMB:** `/usr/OFX/Plugins/RSMB6OFX/rsmb.ofx.bundle/Contents/Linux-x86-64/rsmb.ofx`
  - **Regular RSMB:** `/usr/OFX/Plugins/RSMB6OFX/rsmbregular.ofx.bundle/Contents/Linux-x86-64/rsmbregular.ofx`
  - **Vector RSMB:** `/usr/OFX/Plugins/RSMB6OFX/rsmbvectors.ofx.bundle/Contents/Linux-x86-64/rsmbvectors.ofx`
- **Status:** ✅ Registered (Standard OFX directory)
- **Features:** Motion blur effects (main, regular, and vector-based)
- **Discovery:** Automatically loaded from `/usr/OFX/Plugins/`

### Plugin Summary
- **Total Nuke Plugins (.so):** 1 (KeenTools)
- **Total OFX Plugins (.ofx):** 4 (1 NeatVideo + 3 RSMB variants)
- **All plugins accessible to Nuke** via standard plugin discovery paths
- **No manual configuration required** - plugins auto-discovered on Nuke startup

### Sample Files
- **SimpleNuke-16.nk** - Basic compositing test
- **motionblur2d_10.nk** - Motion blur example
- **render_simple_effects.py** - Python render script

## Container Features

- Based on Rocky Linux 8 for stability
- All X11/XCB dependencies included
- Optimized for headless rendering
- OFX plugin paths pre-configured
- Non-root user execution (nuke:nuke)

## File Structure

```
nuke14/
├── Dockerfile                                  # Container definition
├── Nuke14.1v8-linux-x86_64.tgz                # Nuke installer
├── keentools-2025.2.0-for-nuke-14.1-linux.zip # KeenTools plugin
├── NeatVideo6OFX.Demo.Intel64.tgz             # NeatVideo plugin
├── RSMB6OFXInstaller.tar.gz                   # RSMB plugin
├── run_simple_effects.sh                      # Launch script
├── render_simple_effects.py                   # Render script
├── motionblur2d_10.nk                         # Sample scene
└── testjob-nuke/
    ├── SimpleNuke-16.0.nk                     # Test scene
    └── simple-16.0.png                        # Test asset
```

## Plugin Discovery

Nuke automatically scans these directories for plugins on startup:

### OFX Plugin Paths (Linux)
- `/usr/OFX/Nuke` - Nuke-specific OFX plugins
- `/usr/OFX/Plugins` - Standard OFX plugins ✅ (NeatVideo & RSMB installed here)

### Nuke Plugin Paths
- `/usr/local/NUKE/14.1/plugins/` ✅ (KeenTools installed here)

All plugins are properly registered and will be automatically discovered by Nuke.

## Rendering Commands

### Basic Rendering
```bash
# Run with included test scene
docker run --rm -v $(pwd):/workspace nuke14-plugins-final \
    /opt/nuke/Nuke14.1 -x /samples/SimpleNuke-16.nk

# Render with Python script
docker run --rm -v $(pwd):/workspace nuke14-plugins-final \
    /opt/nuke/Nuke14.1 -t /samples/render_script.py

# Interactive shell
docker run -it --rm nuke14-plugins-final bash
```

### Using Launch Scripts
```bash
# Simple effects render
./run_simple_effects.sh

# Effects render
./run_effects_render.sh

# Pre-2025 MVA render
./run_pre2025mva_render.sh
```

### Output Files
- Rendered images are saved to the output directory specified in the Nuke script
- Use volume mounts to access output on the host system

## License Configuration

The container expects Nuke license server to be accessible. Configure license environment variables as needed:

```bash
docker run --rm \
    -e foundry_LICENSE=port@server \
    -v $(pwd):/workspace \
    nuke14-plugins-final
```

## Troubleshooting

### Common Issues

**Plugin Not Loading:**
- Check plugin paths: `/usr/OFX/Plugins/` and `/usr/local/NUKE/14.1/plugins/`
- Verify OFX bundle structure includes `Contents/Linux-x86-64/`
- Check Nuke startup logs for plugin discovery messages

**License Errors:**
- Verify license server connectivity
- Check firewall rules for license port access
- Ensure `foundry_LICENSE` environment variable is set

**Rendering Issues:**
- Use absolute paths for input files
- Check file permissions in mounted volumes
- Verify all required assets are accessible

### Testing Installation
```bash
# Test Nuke version
docker run --rm nuke14-plugins-final /opt/nuke/Nuke14.1 --version

# List installed plugins
docker run --rm nuke14-plugins-final find /usr/OFX/Plugins -name "*.ofx"
docker run --rm nuke14-plugins-final find /usr/local/NUKE/14.1/plugins -name "*.so"

# Interactive shell for debugging
docker run -it --rm nuke14-plugins-final bash
```

### Docker Run Command Explanation

The launch scripts use several important Docker flags:

```bash
docker run -it --rm \
    --name "nuke14-render" \
    --network host \
    --volume "$(pwd):/workspace" \
    --workdir /workspace \
    nuke14-plugins-final
```

**Key Parameters:**
- `--network host` - Shares host network for license server access
- `--volume "$(pwd):/workspace"` - Mounts current directory for file sharing
- `--workdir /workspace` - Sets working directory to mounted folder
- `-it` - Interactive terminal for real-time output
- `--rm` - Auto-cleanup removes container when stopped

**License Server Access:**
- Container can reach license servers on host network
- No port mapping needed with `--network host`

**File Sharing:**
- Host folder → Container `/workspace/`
- Renders save to accessible location
- Nuke scripts, assets, textures shared bidirectionally

## Performance Notes

- Container uses all available host memory (no memory limit)
- Optimized for CPU rendering
- All dependencies pre-installed for fast startup
- Plugin binaries are pre-compiled for Linux x86_64
- To set a memory limit, add `--memory=XGg` to docker run command

## Version Information

- **Base OS**: Rocky Linux 8
- **Nuke**: 14.1v8
- **KeenTools**: 2025.2.0
- **NeatVideo**: 6 OFX Demo
- **RSMB**: 6 OFX (6.6.2)
- **FFmpeg**: Latest from RPM Fusion

Built and tested on Linux x86_64.

## Plugin Installation Details

### Installation Methods Used

**KeenTools:**
- Method: Manual extraction using `--noexec` flag
- Reason: Installer checksum issues with automated installation
- Result: Successfully extracted to Nuke plugins directory

**NeatVideo:**
- Method: Silent installation with `--mode silent`
- Result: Installed to standard OFX location with symlink

**RSMB:**
- Method: Silent installation with `--mode unattended`
- Result: Installed 3 OFX variants (main, regular, vectors)

All plugins are production-ready and fully functional.

## Publishing to AWS ECR

To build and publish this container to Amazon Elastic Container Registry (ECR):

### 1. Create ECR Repository
```bash
# Create repository
aws ecr create-repository --repository-name nuke14-plugins --region us-west-2
```

### 2. Build and Tag Container
```bash
# Build the container
docker build -t nuke14-plugins-final .

# Tag for ECR (replace with your account ID and region)
docker tag nuke14-plugins-final:latest [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/nuke14-plugins:latest
docker tag nuke14-plugins-final:latest [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/nuke14-plugins:v14.1v8

# Example with actual values:
# docker tag nuke14-plugins-final:latest 123456789012.dkr.ecr.us-west-2.amazonaws.com/nuke14-plugins:latest
```

### 3. Login and Push to ECR
```bash
# Login to ECR
aws ecr get-login-password --region [REGION] | docker login --username AWS --password-stdin [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com

# Push both tags
docker push [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/nuke14-plugins:latest
docker push [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/nuke14-plugins:v14.1v8
```

### 4. Using from ECR
```bash
# Pull from ECR
docker pull [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/nuke14-plugins:latest

# Run from ECR
docker run -it --rm \
    --name nuke14-render \
    --volume "$(pwd):/workspace" \
    [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/nuke14-plugins:latest
```

### Notes
- Replace `[ACCOUNT_ID]` with your 12-digit AWS account ID
- Replace `[REGION]` with your preferred AWS region
- Ensure AWS CLI is configured with appropriate permissions
- Container size is approximately 20GB due to Nuke and plugin installations

## Development and Iteration Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        NUKE 14 + PLUGINS WORKFLOW                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Installation   │    │   Plugin Setup  │    │   Container     │
│     Files       │───▶│   & Extract     │───▶│     Build       │
│                 │    │                 │    │                 │
│ • Nuke.tgz      │    │ • KeenTools     │    │ docker build    │
│ • KeenTools.zip │    │ • NeatVideo     │    │                 │
│ • NeatVideo.tgz │    │ • RSMB          │    │ Creates image   │
│ • RSMB.tar.gz   │    │                 │    │ with all deps   │
│                 │    │ Silent install  │    │ & plugins       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Development   │    │   Local Test    │    │   Production    │
│   & Testing     │◀───│    Renders      │◀───│   Container     │
│                 │    │                 │    │                 │
│ • Edit scripts  │    │ ./run_simple_   │    │ Ready for:      │
│ • Debug issues  │    │   effects.sh    │    │ • ECR upload    │
│ • Test plugins  │    │                 │    │ • Batch jobs    │
│                 │    │ Nuke -x scene.nk│    │ • CI/CD         │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Host Files    │    │   Render Output │    │   Cloud Deploy  │
│                 │    │                 │    │                 │
│ /workspace/     │    │ output/*.exr    │    │ ECR Registry    │
│ • .nk scripts   │    │ • Frame files   │    │ • Tagged images │
│ • Assets        │    │ • Sequences     │    │ • Version ctrl  │
│ • Footage       │    │ • Logs          │    │ • Auto-scaling  │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              ITERATION CYCLE                                │
│                                                                             │
│  1. Place installation files  →  2. Build container                        │
│  3. Test with sample scene    →  4. Verify plugins loaded                  │
│  5. Debug/adjust if needed    →  6. Production render                      │
│  7. Upload to ECR (optional)  →  8. Deploy for batch processing           │
│                                                                             │
│  Quick Commands:                                                            │
│  • Test: docker run --rm nuke14-plugins-final /opt/nuke/Nuke14.1 --version│
│  • Render: ./run_simple_effects.sh                                         │
│  • Debug: docker run -it --rm nuke14-plugins-final bash                   │
│  • Plugins: docker run --rm nuke14-plugins-final find /usr/OFX/Plugins    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Additional Resources

- [Nuke Documentation](https://learn.foundry.com/nuke/)
- [OFX Plugin Standard](http://openeffects.org/)
- [KeenTools Documentation](https://keentools.io/documentation)
- [NeatVideo Manual](https://www.neatvideo.com/support/how-to-use)
- [RSMB Documentation](https://revisionfx.com/products/rsmb/)

## Support

For issues related to:
- **Nuke**: Contact Foundry support
- **KeenTools**: team@keentools.io
- **NeatVideo**: ABSoft support
- **RSMB**: REVisionFX support
- **Container**: Check troubleshooting section above
