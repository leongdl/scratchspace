# ComfyUI Wan 2.2 S2V — Development Guide

End-to-end guide for building the container, configuring Deadline Cloud, and running the `comfy-dag.json` workflow as a batch job.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Your Machine                                                        │
│                                                                      │
│  comfy-demo/                                                         │
│  ├── Dockerfile              # Base: Rocky 9 + CUDA 12.6 + torch 2.7│
│  ├── Dockerfile.wan22-s2v    # S2V layer: 5 models baked in (~24GB)  │
│  ├── comfy-dag.json          # ComfyUI workflow (UI format)          │
│  ├── comfy-dag-api.json      # ComfyUI workflow (API format)         │
│  └── job/                                                            │
│      ├── template.yaml       # Deadline Cloud job template           │
│      └── submit.sh           # Job submission script                 │
└──────────────────────────────────────────────────────────────────────┘
         │
         │  docker build + docker push
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  AWS ECR                                                             │
│  <account>.dkr.ecr.us-west-2.amazonaws.com/comfyui-wan22-s2v:latest │
└──────────────────────────────────────────────────────────────────────┘
         │
         │  deadline bundle submit
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Deadline Cloud                                                      │
│                                                                      │
│  Farm ──► Queue ──► Fleet (GPU worker)                               │
│                         │                                            │
│                         ├── Pulls container from ECR                 │
│                         ├── Starts ComfyUI with --runtime=nvidia     │
│                         ├── Submits workflow via /api/prompt          │
│                         ├── Polls /api/history until complete         │
│                         └── Collects output video (MP4)              │
└──────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI v2 configured with credentials
- Deadline Cloud CLI (`pip install deadline`)
- Docker (for local builds)
- A Deadline Cloud farm with a GPU fleet (g6.xlarge or g6e.xlarge)

## Step 1 — Build the Docker Image

```bash
cd comfy-demo

# Build base image (CUDA 12.6 + torch 2.7.0 + ComfyUI)
docker build -t comfyui-rocky:latest -f Dockerfile .

# Build S2V layer (downloads ~24GB of models)
docker build -t comfyui-wan22-s2v:latest -f Dockerfile.wan22-s2v .
```

The base image uses `nvidia/cuda:12.6.3-devel-rockylinux9` with torch 2.7.0+cu126, matching the pattern from the Trellis2 container. PyTorch 2.7 dropped cu124 wheels, so cu126 is the minimum.

### Image sizes

| Image | Size |
|-------|------|
| comfyui-rocky:latest | ~20GB |
| comfyui-wan22-s2v:latest | ~70GB |

## Step 2 — Push to ECR

```bash
# Set your account and region
ACCOUNT_ID="<your-account-id>"
REGION="us-west-2"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO_NAME="comfyui-wan22-s2v"

# Create ECR repo (once)
aws ecr create-repository --repository-name $REPO_NAME --region $REGION

# Login to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Tag and push
docker tag comfyui-wan22-s2v:latest ${ECR_REGISTRY}/${REPO_NAME}:latest
docker push ${ECR_REGISTRY}/${REPO_NAME}:latest
```

## Step 3 — Configure Deadline Cloud IAM

The fleet role and queue role both need ECR pull access so workers can authenticate and pull the container image.

### Queue Role

Attach `AmazonEC2ContainerRegistryReadOnly` (or `FullAccess`) to your queue's IAM role:

```bash
QUEUE_ROLE_NAME="<your-queue-role-name>"

aws iam attach-role-policy \
  --role-name $QUEUE_ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### Fleet (Worker) Role

Attach the same ECR policy to the fleet's IAM role:

```bash
FLEET_ROLE_NAME="<your-fleet-role-name>"

aws iam attach-role-policy \
  --role-name $FLEET_ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

## Step 4 — Configure Worker Host

Workers need Docker + NVIDIA Container Toolkit installed. Use the host config script as the fleet's host configuration command, or run it manually on the worker:

```bash
bash comfy-demo/setup/host_config.sh
```

This installs:
- Docker with NVIDIA runtime
- nvidia-container-toolkit + CDI spec
- 32GB swap file (needed for 16GB RAM instances like g6.xlarge)

For Deadline Cloud fleets, paste the contents of `host_config.sh` into the fleet's "Host configuration" script in the console, or reference it via the CLI.

## Step 5 — Submit the Job

```bash
cd comfy-demo/job

# Edit submit.sh with your farm/queue IDs, then:
bash submit.sh
```

Or submit directly:

```bash
deadline bundle submit comfy-demo/job \
  --farm-id farm-XXXXX \
  --queue-id queue-XXXXX \
  --name "Wan22-S2V-Render" \
  --max-retries-per-task 1
```

The job template expects three input files as attachments:
- `comfy-dag-api.json` — the workflow in ComfyUI API format
- `image.jpg` — reference face image
- `mary-had-a-little-lamb.mp3` — audio clip

These are specified as `PATH` parameters in `template.yaml` and uploaded as job attachments.

## VRAM and Instance Selection

The startup script auto-detects GPU VRAM and enables `--lowvram` on GPUs with ≤24GB:

| Instance | GPU | VRAM | Mode | Notes |
|----------|-----|------|------|-------|
| g6.xlarge | L4 | 24GB | --lowvram (auto) | Works but slower, needs 32GB swap |
| g6e.xlarge | L40S | 48GB | normal (auto) | Recommended for production |
| g6e.2xlarge | L40S | 48GB | normal (auto) | More CPU/RAM headroom |

To override auto-detection, pass environment variables when running the container:
- `-e LOW_VRAM=true` — force low VRAM mode
- `-e AUTO_VRAM=false` — disable auto-detection, use normal mode

## Baked Models

All models are downloaded during `docker build` and baked into the image. No runtime downloads needed.

| Model | Directory | Size |
|-------|-----------|------|
| wan2.2_s2v_14B_fp8_scaled.safetensors | diffusion_models/ | 16GB |
| umt5_xxl_fp8_e4m3fn_scaled.safetensors | text_encoders/ | 6.3GB |
| wan_2.1_vae.safetensors | vae/ | 243MB |
| wav2vec2_large_english_fp16.safetensors | audio_encoders/ | 602MB |
| wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors | loras/ | 1.2GB |
| taew2_1.safetensors | vae_approx/ | 22MB |

## Local Testing

Run the container locally (requires NVIDIA GPU + docker with nvidia runtime):

```bash
docker run -d \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --network host \
  --name comfyui-session \
  comfyui-wan22-s2v:latest
```

Then open `http://localhost:8188` and load `comfy-dag.json`.

## Troubleshooting

### "no space left on device" during docker run
The VOLUME directive in the base Dockerfile causes Docker to copy baked models into an anonymous volume on first run. This doubles disk usage. Ensure at least 200GB on the root volume, or use `--mount` bind mounts instead.

### torch.AcceleratorError crash on OOM
The Dockerfile patches ComfyUI's `model_management.py` to handle this. If you see this error, the patch wasn't applied — rebuild the base image.

### Container starts but workflow OOMs
On L4 (24GB), the auto-detect enables `--lowvram`. If it still OOMs, use a g6e.xlarge (L40S 48GB).
