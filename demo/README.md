# Houdini + RenderMan Docker Container

A complete Docker setup for running Houdini 20.0.896 with RenderMan 26.3 for headless rendering.

## Prerequisites

- Docker installed and running
- Valid Houdini and RenderMan licenses
- License servers accessible from the container

## Quick Start

### Option 1: Use Included Versions (Recommended)
1. **Build the container:**
   ```bash
   docker build -t houdini-rdman:latest .
   ```

2. **Run a test render:**
   ```bash
   ./run-houdini-rdman.sh "hrender -v -d renderman1 /workspace/RMAN_test_02.hip"
   ```

### Option 2: Configure for Different Versions
If you have different Houdini or RenderMan versions:

1. **Place your installation files in this directory:**
   - `houdini-X.X.XXX-linux_x86_64_gcc11.2.tar.gz`
   - `RenderManForHoudini-XX.X_XXXXXXX-linuxRHEL9_gcc11icx232.x86_64.rpm`
   - `RenderManProServer-XX.X_XXXXXXX-linuxRHEL9_gcc11icx232.x86_64.rpm`

2. **Run the configuration script:**
   ```bash
   ./configure.sh
   ```
   The script will:
   - Auto-detect your installation files
   - Extract version numbers
   - Let you select which versions to use
   - Update Dockerfile and run script automatically
   - Create backups of original files

3. **Build and test:**
   ```bash
   docker build -t houdini-rdman:latest .
   ./run-houdini-rdman.sh "hrender -v -d renderman1 /workspace/RMAN_test_02.hip"
   ```

## What's Included

- **Houdini 20.0.896** - Latest stable release
- **RenderMan ProServer 26.3** - Production renderer
- **RenderMan for Houdini 26.3** - Houdini integration
- **Sample scene** - RMAN_test_02.hip for testing
- **Launch script** - run-houdini-rdman.sh for easy execution

## Container Features

- Based on Rocky Linux 9 for stability
- All X11/XCB dependencies included
- Optimized for headless rendering
- License environment pre-configured

## File Structure

```
demo/
├── Dockerfile                          # Container definition
├── run-houdini-rdman.sh               # Launch script
├── RMAN_test_02.hip                   # Sample Houdini scene
├── houdini-20.0.896-linux_x86_64_gcc11.2.tar.gz
├── RenderManForHoudini-26.3_2352169-linuxRHEL9_gcc11icx232.x86_64.rpm
└── RenderManProServer-26.3_2352291-linuxRHEL9_gcc11icx232.x86_64.rpm
```

## License Configuration

The container expects these license servers to be accessible:
- **Houdini**: `localhost:1715` (SESI_LMHOST)
- **RenderMan**: `9010@localhost` (PIXAR_LICENSE_FILE)

Update the license server addresses in `run-houdini-rdman.sh` as needed.

## Rendering Commands

### Basic Rendering
```bash
# Render default frame
./run-houdini-rdman.sh "hrender -v -d renderman1 /workspace/scene.hip"

# Render with included test scene (outputs to render/ folder)
./run-houdini-rdman.sh "hrender -v -F 8 -d renderman1 /workspace/RMAN_test_02.hip"

# Render specific frame
./run-houdini-rdman.sh "hrender -v -F 10 -d renderman1 /workspace/scene.hip"

# Render frame range
./run-houdini-rdman.sh "hrender -e -f 1 10 -d renderman1 /workspace/scene.hip"
```

### Output Files
- Rendered images are saved to: `render/scene_name.driver_name.XXXX.exr`
- Use `find . -name "*.exr"` to locate output files
- Copy to host with: `docker cp container:/workspace/render/ ./output/`

## Troubleshooting

### Common Issues
- **Segmentation faults**: Use absolute paths (`/workspace/file.hip`)
- **Missing drivers**: Check render node names with `-d driver_name`
- **License errors**: Verify license server connectivity
- **DSO errors**: Already configured with `HOUDINI_DSO_ERROR=0` (permissive mode). For debugging DSO issues, set `HOUDINI_DSO_ERROR=2` (warnings) or `HOUDINI_DSO_ERROR=3` (verbose) in the run script

### Testing Installation
```bash
# Test RenderMan
./run-houdini-rdman.sh "prman -version"

# Test Houdini
./run-houdini-rdman.sh "hrender --help"

# Interactive shell
./run-houdini-rdman.sh
```

### Docker Run Command Explanation

The `run-houdini-rdman.sh` script uses several important Docker flags:

```bash
docker run -it --rm \
    --name "houdini-rdman-rhel" \
    --network host \
    --ulimit stack=52428800 \
    --volume "$(pwd):/workspace" \
    --workdir /workspace \
    houdini-rdman:latest
```

**Key Parameters:**
- `--network host` - **Shares host network stack** with container, allowing direct access to license servers running on localhost (ports 1715 for Houdini, 9010 for RenderMan)
- `--volume "$(pwd):/workspace"` - **Mounts current directory** as `/workspace` inside container, enabling file sharing between host and container
- `--workdir /workspace` - **Sets working directory** to the mounted folder, so renders output to accessible location
- `--ulimit stack=52428800` - **Increases stack size** for Houdini's memory requirements
- `-it` - **Interactive terminal** for shell access and real-time output
- `--rm` - **Auto-cleanup** removes container when stopped

**License Server Access:**
The `--network host` flag is crucial for license connectivity:
- Container can reach `localhost:1715` (Houdini license server)
- Container can reach `localhost:9010` (RenderMan license server)
- No port mapping needed - direct host network access

**File Sharing:**
- Host `demo/` folder → Container `/workspace/`
- Renders save to `render/` subfolder (accessible on host)
- Hip files, assets, textures shared bidirectionally

## Performance Notes

- Container uses all available host memory (no memory limit)
- Optimized for CPU rendering
- All dependencies pre-installed for fast startup
- Single-layer builds for efficient caching
- To set a memory limit, add `--memory=XGg` to the docker run command in run-houdini-rdman.sh

## Version Information

- **Base OS**: Rocky Linux 9
- **Houdini**: 20.0.896
- **RenderMan ProServer**: 26.3
- **RenderMan for Houdini**: 26.3
- **Python**: 3.10 with required packages

Built and tested on Linux x86_64 with gcc 11.2.

## Publishing to AWS ECR

To build and publish this container to Amazon Elastic Container Registry (ECR):

### 1. Create ECR Repository
```bash
# Create repository (replace region and account as needed)
aws ecr create-repository --repository-name houdini-rdman --region us-west-2
```

### 2. Build and Tag Container
```bash
# Build the container
docker build -t houdini-rdman:latest .

# Tag for ECR (replace with your account ID and region)
docker tag houdini-rdman:latest [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/houdini-rdman:latest
docker tag houdini-rdman:latest [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/houdini-rdman:v26.3-h20.0.896

# Example with actual values:
# docker tag houdini-rdman:latest 123456789012.dkr.ecr.us-west-2.amazonaws.com/houdini-rdman:latest
# docker tag houdini-rdman:latest 123456789012.dkr.ecr.us-west-2.amazonaws.com/houdini-rdman:v26.3-h20.0.896
```

### 3. Login and Push to ECR
```bash
# Login to ECR
aws ecr get-login-password --region [REGION] | docker login --username AWS --password-stdin [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com

# Push both tags
docker push [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/houdini-rdman:latest
docker push [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/houdini-rdman:v26.3-h20.0.896
```

### 4. Complete Example Script
```bash
#!/bin/bash
# Set your AWS account details
ACCOUNT_ID="123456789012"
REGION="us-west-2"
REPO_NAME="houdini-rdman"

# Create repository
aws ecr create-repository --repository-name $REPO_NAME --region $REGION

# Build container
docker build -t $REPO_NAME:latest .

# Tag for ECR
docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest
docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:v26.3-h20.0.896

# Login to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Push to ECR
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:v26.3-h20.0.896

echo "Container published to ECR:"
echo "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"
echo "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:v26.3-h20.0.896"
```

### 5. Using from ECR
```bash
# Pull from ECR
docker pull [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/houdini-rdman:latest

# Run from ECR
docker run -it --rm \
    --name houdini-rdman \
    --volume "$(pwd):/workspace" \
    [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/houdini-rdman:latest
```

### Notes
- Replace `[ACCOUNT_ID]` with your 12-digit AWS account ID
- Replace `[REGION]` with your preferred AWS region (e.g., us-west-2, us-east-1)
- Ensure AWS CLI is configured with appropriate permissions
- Container size is approximately 8-10GB due to Houdini and RenderMan installations
- Consider using multi-stage builds for production to reduce image size
#
# Development and Iteration Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HOUDINI + RENDERMAN WORKFLOW                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Installation   │    │   Configuration │    │   Container     │
│     Files       │───▶│     Script      │───▶│     Build       │
│                 │    │                 │    │                 │
│ • houdini.tar.gz│    │ ./configure.sh  │    │ docker build    │
│ • RFH.rpm       │    │                 │    │                 │
│ • RPS.rpm       │    │ Auto-detects    │    │ Creates image   │
│                 │    │ versions &      │    │ with all deps   │
│                 │    │ updates paths   │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Development   │    │   Local Test    │    │   Production    │
│   & Testing     │◀───│    Renders      │◀───│   Container     │
│                 │    │                 │    │                 │
│ • Edit scenes   │    │ ./run-houdini-  │    │ Ready for:      │
│ • Debug issues  │    │   rdman.sh      │    │ • ECR upload    │
│ • Iterate       │    │                 │    │ • Batch jobs    │
│                 │    │ hrender -v -d   │    │ • CI/CD         │
│                 │    │ renderman1      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Host Files    │    │   Render Output │    │   Cloud Deploy  │
│                 │    │                 │    │                 │
│ /workspace/     │    │ render/*.exr    │    │ ECR Registry    │
│ • .hip scenes   │    │ • Frame files   │    │ • Tagged images │
│ • Assets        │    │ • Sequences     │    │ • Version ctrl  │
│ • Textures      │    │ • Logs          │    │ • Auto-scaling  │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              ITERATION CYCLE                                │
│                                                                             │
│  1. Place installation files  →  2. Run ./configure.sh                     │
│  3. Build container           →  4. Test with sample scene                 │
│  5. Debug/adjust if needed    →  6. Production render                      │
│  7. Upload to ECR (optional)  →  8. Deploy for batch processing           │
│                                                                             │
│  Quick Commands:                                                            │
│  • Test: ./run-houdini-rdman.sh "prman -version"                          │
│  • Render: ./run-houdini-rdman.sh "hrender -v -d renderman1 /workspace/scene.hip" │
│  • Debug: ./run-houdini-rdman.sh (interactive shell)                      │
└─────────────────────────────────────────────────────────────────────────────┘
```