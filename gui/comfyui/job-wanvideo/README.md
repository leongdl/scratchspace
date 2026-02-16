# Container B: WanVideo 2.1 (AI Video Generation)

## Overview

ComfyUI container for AI video generation using the Wan 2.1 T2V 14B model (fp16). All weights are baked into the container for fast startup. Runs on port 8188.

Only one container runs at a time — swap between TRELLIS-2 and WanVideo as needed.

## Models

| Model | Source | Parameters | Size | Purpose |
|-------|--------|------------|------|---------|
| Wan 2.1 T2V 14B fp16 | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/diffusion_models/wan2.1_t2v_14B_fp16.safetensors) | 14B | ~28GB | Text-to-video diffusion model |
| Wan 2.1 VAE | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/vae/wan_2.1_vae.safetensors) | — | ~300MB | Video VAE decoder |
| UMT5-XXL fp16 | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/text_encoders/umt5_xxl_fp16.safetensors) | — | ~9.5GB | Text encoder |

## How Models Are Loaded (Source-Verified)

All three models use ComfyUI's standard `folder_paths` system. Verified by reading the actual node source code.

### Diffusion Model — `ComfyUI/models/diffusion_models/`

Source: [`ComfyUI-WanVideoWrapper/nodes_model_loading.py` WanVideoModelLoader.INPUT_TYPES()](https://github.com/kijai/ComfyUI-WanVideoWrapper/blob/main/nodes_model_loading.py)

The node lists files from `folder_paths.get_filename_list("diffusion_models")` which resolves to `models/unet/` and `models/diffusion_models/`. It then loads via `folder_paths.get_full_path_or_raise("diffusion_models", model)`.

```python
# From nodes_model_loading.py line ~1080
"model": (folder_paths.get_filename_list("unet_gguf") +
          folder_paths.get_filename_list("diffusion_models"), ...)
# line ~1195
model_path = folder_paths.get_full_path_or_raise("diffusion_models", model)
```

### VAE — `ComfyUI/models/vae/`

Source: [`ComfyUI-WanVideoWrapper/nodes_model_loading.py` WanVideoVAELoader.INPUT_TYPES()](https://github.com/kijai/ComfyUI-WanVideoWrapper/blob/main/nodes_model_loading.py)

Standard `folder_paths.get_filename_list("vae")` → `models/vae/`.

```python
# From nodes_model_loading.py line ~1865
"model_name": (folder_paths.get_filename_list("vae"), ...)
# line ~1886
model_path = folder_paths.get_full_path_or_raise("vae", model_name)
```

### Text Encoder — `ComfyUI/models/text_encoders/`

Source: [`ComfyUI-WanVideoWrapper/nodes_model_loading.py` LoadWanVideoT5TextEncoder.INPUT_TYPES()](https://github.com/kijai/ComfyUI-WanVideoWrapper/blob/main/nodes_model_loading.py)

Standard `folder_paths.get_filename_list("text_encoders")` → `models/text_encoders/` and `models/clip/`.

```python
# From nodes_model_loading.py line ~1950
"model_name": (folder_paths.get_filename_list("text_encoders"), ...)
# line ~1976
model_path = folder_paths.get_full_path_or_raise("text_encoders", model_name)
```

### Weight Paths Summary

All paths are standard ComfyUI `folder_paths` locations under `/opt/comfyui/models/`:

```
/opt/comfyui/models/
├── diffusion_models/
│   └── wan2.1_t2v_14B_fp16.safetensors   # folder_paths "diffusion_models"
├── vae/
│   └── wan_2.1_vae.safetensors            # folder_paths "vae"
└── text_encoders/
    └── umt5_xxl_fp16.safetensors          # folder_paths "text_encoders"
```

### Download URLs (for Dockerfile wget)

```
# Diffusion model (~28GB)
https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_fp16.safetensors

# VAE (~300MB)
https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors

# Text encoder (~9.5GB)
https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors
```

Source: [BadAss Wan Resource List (CivitAI)](https://civitai.com/articles/16983/badass-wan-resource-list)

## Custom Nodes

| Node | Repository | Purpose |
|------|------------|---------|
| ComfyUI-WanVideoWrapper | [kijai/ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper) | WanVideo ComfyUI integration (T2V, I2V, VACE, GGUF, LoRA) |

## Dependencies

- All pip requirements from `ComfyUI-WanVideoWrapper/requirements.txt` (ftfy, accelerate, einops, diffusers, peft, sentencepiece, protobuf, pyloudnorm, gguf, opencv-python, scipy)
- Layers on `comfyui-sdxl:latest` which provides torch 2.6.0+cu124, ComfyUI, and SDXL checkpoints
- No native CUDA extensions needed — pure Python/PyTorch
- **Torch version agnostic**: Unlike TRELLIS-2 (which ships pre-compiled C++/CUDA wheels binary-linked to a specific torch ABI), WanVideoWrapper uses only standard PyTorch ops and pip-installable Python packages. No `.so` files to match, so it runs on torch 2.6.0, 2.7.0, or any compatible version without rebuild

## VRAM Requirements

| Operation | VRAM |
|-----------|------|
| Wan 2.1 14B fp16 inference | ~40GB |
| UMT5-XXL text encoding | ~10GB (offloaded after encoding) |

Requires 48GB VRAM (L40S). The 14B model uses the full GPU.

Source: [CivitAI Wan Resource List — VRAM Considerations](https://civitai.com/articles/16983/badass-wan-resource-list)

## Hardware Target

| Instance | GPU | VRAM | Status |
|----------|-----|------|--------|
| g6e.xlarge | L40S | 48GB | ✅ Primary target |
| p4d.24xlarge | A100 | 40GB | ✅ |
| g5.xlarge | A10G | 24GB | ❌ Insufficient VRAM for 14B |
| g6.xlarge | L4 | 24GB | ❌ Insufficient VRAM for 14B |

## Host Setup

Before building or running, the host needs Docker + NVIDIA Container Toolkit configured. See `gui/design/host_config.md` for full details, or run `gui/design/setup_gpu_docker.sh`.

Key requirements:
- Docker 25.x+
- nvidia-container-toolkit 1.18.2+ (1.18.1 has BPF bug with driver 580.x)
- CDI spec generated: `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`
- Current user in docker group: `sudo usermod -aG docker $USER`

## Build

Requires building the full image chain in order:

```bash
cd gui/comfyui

# 1. Base image (~19GB, ~5 min)
docker build -t comfyui-rocky:latest .

# 2. SDXL layer (~46GB total, ~5 min — downloads ~13GB models)
docker build -f Dockerfile.sdxl -t comfyui-sdxl:latest .

# 3. WanVideo layer (~140GB total, ~10 min — downloads ~38GB models)
docker build -f Dockerfile.wanvideo -t comfyui-wanvideo:latest .
```

Build is straightforward — all models are public ungated HuggingFace repos downloaded via `wget`, and the WanVideoWrapper requirements install cleanly against the base image's torch 2.6.0+cu124. No HF_TOKEN needed. No native CUDA extensions to compile.

Total image size reported by Docker: ~140GB (includes all parent layers). Actual new data: ~50GB (base ~12GB + SDXL ~7GB + Wan 14B ~28GB + VAE ~300MB + UMT5 ~9.5GB + deps).

## Run (Standalone)

**Do not use `--gpus all`** — it fails on NVIDIA driver 580.x due to a BPF device filter bug. Use `--runtime=nvidia` instead:

```bash
docker run -d \
    --runtime=nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    --network host \
    --name comfyui-session \
    comfyui-wanvideo:latest
```

Note: First `docker run` on a 140GB image takes 10-20+ minutes on default gp3 EBS (125 MB/s throughput). Docker is preparing the overlay filesystem. Monitor with `df -h /` (disk usage should grow) and `ps aux | grep "docker run"` (process should be alive). See "Startup Performance" below.

Access ComfyUI at `http://localhost:8188` once the container is healthy.

### Startup Performance

Default gp3 EBS (3000 IOPS / 125 MB/s) makes first container start very slow for large images. Recommended EBS tuning (can be applied live in EC2 Console → Volumes → Modify):

| Setting | Default | Recommended |
|---------|---------|-------------|
| Throughput | 125 MB/s | 1000 MB/s (+$35/mo) |
| IOPS | 3000 | 9000 (+$30/mo) |

Alternative: If the instance has a local NVMe instance store (check `lsblk`), mount it as Docker's data root for much faster I/O at no extra cost.

### Verifying Startup

```bash
# Check container status
docker ps -a

# Watch logs
docker logs -f comfyui-session

# Healthy when you see:
#   "Assets scan(roots=['models']) completed" — models found
#   "To see the GUI go to: http://0.0.0.0:8188" — ready
```

Safe-to-ignore warnings:
- `Could not load sageattention` — optional acceleration
- `FantasyPortrait nodes not available: No module named 'onnx'` — unrelated feature

### Cleanup / Restart

```bash
docker stop comfyui-session
docker rm comfyui-session
# If "name already in use" but docker ps -a shows nothing (ghost ref):
sudo systemctl restart docker
```

## Pipeline

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Text Prompt  │────▶│ Wan 2.1 T2V 14B  │────▶│ Wan 2.1 VAE      │────▶│ Save Video  │
│              │     │ (diffusion)      │     │ (decode)         │     │ (MP4)       │
└──────────────┘     └──────────────────┘     └──────────────────┘     └─────────────┘
```

## Network

- Port: `8188`
- Only one container runs at a time — swap between TRELLIS-2 and WanVideo as needed

## ECR

```bash
docker tag comfyui-wanvideo:latest 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-wanvideo:latest
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-wanvideo:latest
```

## Build Summary

Built and verified locally on g6e.xlarge (L40S 48GB, Amazon Linux 2023, driver 580.126.09).

| Layer | Size | Description |
|-------|------|-------------|
| Base (Rocky Linux 9) | 176MB | OS layer |
| CUDA 12.4 + Python 3.12 + ComfyUI + torch 2.6.0 | ~19GB | Base runtime (`comfyui-rocky:latest`) |
| SDXL checkpoints (inherited) | ~27GB | SDXL models from `comfyui-sdxl:latest` |
| ComfyUI-WanVideoWrapper (git clone) | 67MB | Custom node |
| pip requirements | 331MB | ftfy, accelerate, einops, diffusers, etc. |
| wan2.1_t2v_14B_fp16.safetensors | 28.6GB | Diffusion model (3.7 min download) |
| wan_2.1_vae.safetensors | 254MB | VAE decoder |
| umt5_xxl_fp16.safetensors | 11.4GB | Text encoder (1.6 min download) |
| chown (ownership fix) | 53.6GB | Metadata-only layer (no new data) |
| Image export | ~11 min | Writing layers to disk (slow on default gp3) |

Docker-reported image size: `140GB` (includes all parent layers)
Image: `comfyui-wanvideo:latest`
SHA: `ab3bc564a248`

### Build Chain Timing (g6e.xlarge, default gp3 EBS)

| Step | Time | Notes |
|------|------|-------|
| comfyui-rocky:latest | ~6 min | CUDA toolkit install is heaviest |
| comfyui-sdxl:latest | ~5 min | ~13GB model downloads + 2 min export |
| comfyui-wanvideo:latest | ~17 min | ~38GB model downloads + 11 min export |
| First `docker run` | ~15 min | Overlay filesystem setup (one-time) |
| Total cold start | ~43 min | From bare host to running ComfyUI |

## References

- [Comfy-Org/Wan_2.1_ComfyUI_repackaged (HuggingFace)](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged)
- [Wan-AI/Wan2.1-T2V-14B (HuggingFace)](https://huggingface.co/Wan-AI/Wan2.1-T2V-14B)
- [kijai/ComfyUI-WanVideoWrapper (GitHub)](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [BadAss Wan Resource List (CivitAI)](https://civitai.com/articles/16983/badass-wan-resource-list)
- [Wan-Video/Wan2.1 (GitHub)](https://github.com/Wan-Video/Wan2.1)
