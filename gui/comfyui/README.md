# ComfyUI on Deadline Cloud

Rocky Linux 9 container running ComfyUI with NVIDIA GPU support, designed for Deadline Cloud SMF workers with reverse tunnel access.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              NETWORK FLOW                                       │
└─────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Deadline Worker │     │   VPC Lattice    │     │  EC2 Proxy       │     │    Your Mac      │
│  (CMF Container) │     │   Endpoint       │     │  (10.0.0.65)     │     │                  │
├──────────────────┤     ├──────────────────┤     ├──────────────────┤     ├──────────────────┤
│                  │     │                  │     │                  │     │                  │
│  ComfyUI         │     │  rcfg-011bc...   │     │                  │     │  Browser         │
│  :8188           │────▶│  .resource-      │────▶│  :8188           │◀────│  localhost:8188  │
│                  │ SSH │  endpoints...    │     │  (listening)     │ SSM │                  │
│  (localhost)     │ -R  │                  │     │                  │     │                  │
│                  │     │                  │     │                  │     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘     └──────────────────┘
        │                        │                        │                        │
        │   Reverse SSH Tunnel   │                        │   SSM Port Forward     │
        │   -R 8188:localhost:8188                        │   localPort:8188       │
        │                        │                        │   remotePort:8188      │
        └────────────────────────┘                        └────────────────────────┘


STEP 1: Worker → VPC Lattice → EC2 (Reverse SSH Tunnel)
   ssh -R 8188:localhost:8188 ssm-user@rcfg-011bc61e9efbfbd1e.resource-endpoints.deadline.us-west-2.amazonaws.com

STEP 2: Mac → EC2 (SSM Port Forward)
   aws ssm start-session --target i-XXXXX --document-name AWS-StartPortForwardingSession ...
```

## Quick Start

### 1. Build the Container

```bash
# Basic build
docker build -t comfyui-rocky:latest .

# With specific CUDA version
docker build --build-arg CUDA_VERSION=12.4 -t comfyui-rocky:cu124 .
```

### 2. Pre-bake Models (Optional)

Create a derived image with models pre-installed:

```dockerfile
FROM comfyui-rocky:latest

# Download SD 1.5 checkpoint
RUN wget -O /opt/comfyui/models/checkpoints/v1-5-pruned-emaonly.safetensors \
    https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors

# Download SDXL checkpoint
RUN wget -O /opt/comfyui/models/checkpoints/sd_xl_base_1.0.safetensors \
    https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
```

### 3. Run Locally (Testing)

```bash
# With GPU
docker run --gpus all -p 8188:8188 \
    -v ./models:/opt/comfyui/models \
    -v ./output:/opt/comfyui/output \
    comfyui-rocky:latest

# CPU only
docker run -p 8188:8188 \
    -e CPU_ONLY=true \
    -v ./models:/opt/comfyui/models \
    comfyui-rocky:latest
```

### 4. Deploy to Deadline Cloud

See `job/` directory for Deadline job templates.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `COMFYUI_PORT` | 8188 | Web interface port |
| `COMFYUI_LISTEN` | 0.0.0.0 | Listen address |
| `EC2_PROXY_HOST` | - | EC2 proxy IP for reverse tunnel |
| `EC2_PROXY_PORT` | 6688 | Remote port on EC2 proxy |
| `EC2_PROXY_USER` | ec2-user | SSH user on EC2 proxy |
| `SSH_KEY_PATH` | /home/comfyui/.ssh/id_rsa | SSH key for tunnel |
| `PREVIEW_METHOD` | - | Preview method (auto, taesd) |
| `ENABLE_MANAGER` | false | Enable ComfyUI-Manager |
| `LOW_VRAM` | false | Enable low VRAM mode |
| `HIGH_VRAM` | false | Enable high VRAM mode |
| `CPU_ONLY` | false | Run on CPU only |
| `EXTRA_ARGS` | - | Additional ComfyUI arguments |

## Volume Mounts

| Path | Description |
|------|-------------|
| `/opt/comfyui/models` | AI model files |
| `/opt/comfyui/input` | Input images |
| `/opt/comfyui/output` | Generated outputs |
| `/opt/comfyui/custom_nodes` | Custom node extensions |

## Model Directory Structure

```
models/
├── checkpoints/     # Main model files (.safetensors, .ckpt)
├── clip/            # CLIP models
├── clip_vision/     # CLIP vision models
├── controlnet/      # ControlNet models
├── embeddings/      # Textual inversion embeddings
├── loras/           # LoRA models
├── upscale_models/  # Upscaling models (ESRGAN, etc.)
├── vae/             # VAE models
└── vae_approx/      # TAESD preview decoders
```

## Pre-baked Model Images

Create specialized images with models pre-installed:

### SD 1.5 Image
```bash
docker build -f Dockerfile.sd15 -t comfyui-sd15:latest .
```

### SDXL Image
```bash
docker build -f Dockerfile.sdxl -t comfyui-sdxl:latest .
```

### Flux Image
```bash
docker build -f Dockerfile.flux -t comfyui-flux:latest .
```

## Reverse Tunnel Setup

### On EC2 Proxy Instance

1. Enable GatewayPorts in sshd:
```bash
sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

2. Run socat proxy:
```bash
socat TCP-LISTEN:8188,fork,reuseaddr TCP:localhost:6688
```

### From Your Mac

1. Find your EC2 instance ID:
```bash
aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=10.0.0.65" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text \
  --region us-west-2
```

2. Start SSM port forward:
```bash
aws ssm start-session \
    --target i-XXXXXXXXX \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["8188"],"localPortNumber":["8188"]}' \
    --region us-west-2
```

3. Open browser: **http://localhost:8188**

## Troubleshooting

### GPU Not Detected
- Ensure NVIDIA drivers are installed on host
- Use `--gpus all` flag with docker run
- Check `nvidia-smi` works inside container

### Out of Memory
- Use `LOW_VRAM=true` environment variable
- Reduce batch size in workflows
- Use smaller models (SD 1.5 vs SDXL)

### Tunnel Connection Failed
- Verify EC2 security group allows SSH from worker subnet
- Check SSH key is in EC2's authorized_keys
- Ensure GatewayPorts is enabled on EC2
