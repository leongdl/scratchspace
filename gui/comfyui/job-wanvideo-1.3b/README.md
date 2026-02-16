# Container: WanVideo 2.1 T2V 1.3B (Lightweight AI Video Generation)

## Overview

ComfyUI container for AI video generation using the Wan 2.1 T2V 1.3B model (fp16). Smaller and faster alternative to the 14B variant. All weights are baked into the container for fast startup. Runs on port 8188.

Only one container runs at a time — swap between TRELLIS-2, WanVideo 14B, and WanVideo 1.3B as needed.

## Models

| Model | Source | Parameters | Size | Purpose |
|-------|--------|------------|------|---------|
| Wan 2.1 T2V 1.3B fp16 | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors) | 1.3B | ~2.6GB | Text-to-video diffusion model |
| Wan 2.1 VAE | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/vae/wan_2.1_vae.safetensors) | — | ~300MB | Video VAE decoder |
| UMT5-XXL fp16 | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/text_encoders/umt5_xxl_fp16.safetensors) | — | ~9.5GB | Text encoder |

## 14B vs 1.3B Comparison

| Aspect | 14B | 1.3B |
|--------|-----|------|
| Diffusion model size | ~28GB | ~2.6GB |
| Total image size | ~140GB | ~115GB |
| VRAM required | ~40GB (L40S/A100) | ~8GB (L4/A10G/RTX 4090) |
| RAM swap needed | Yes (on ≤32GB) | No |
| Video quality | Higher detail, coherence | Good for prototyping |
| Generation speed | Slower | Faster |
| Min GPU | L40S 48GB | L4 24GB |


## How Models Are Loaded

Same as the 14B variant — all three models use ComfyUI's standard `folder_paths` system. See `job-wanvideo/README.md` for source-verified loading details.

### Weight Paths Summary

```
/opt/comfyui/models/
├── diffusion_models/
│   └── wan2.1_t2v_1.3B_fp16.safetensors   # folder_paths "diffusion_models"
├── vae/
│   └── wan_2.1_vae.safetensors             # folder_paths "vae"
└── text_encoders/
    └── umt5_xxl_fp16.safetensors           # folder_paths "text_encoders"
```

## Custom Nodes

Same as 14B variant:

| Node | Repository | Purpose |
|------|------------|---------|
| ComfyUI-WanVideoWrapper | [kijai/ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper) | WanVideo ComfyUI integration |
| ComfyUI-VideoHelperSuite | [Kosinkadink/ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite) | MP4/video output |

## VRAM Requirements

| Operation | VRAM |
|-----------|------|
| Wan 2.1 1.3B fp16 inference | ~8GB |
| UMT5-XXL text encoding | ~10GB (offloaded after encoding) |

Can run on 24GB GPUs (L4, A10G) or even consumer RTX 4090.

## Hardware Target

| Instance | GPU | VRAM | RAM | Status |
|----------|-----|------|-----|--------|
| g6.xlarge | L4 | 24GB | 16GB | ✅ Primary target |
| g5.xlarge | A10G | 24GB | 16GB | ✅ |
| g6e.xlarge | L40S | 48GB | 30GB | ✅ Overkill but works |
| g6e.2xlarge | L40S | 48GB | 64GB | ✅ |

## Build

```bash
cd gui/comfyui

# 1. Base image (~19GB, ~5 min)
docker build -t comfyui-rocky:latest .

# 2. SDXL layer (~46GB total, ~5 min)
docker build -f Dockerfile.sdxl -t comfyui-sdxl:latest .

# 3. WanVideo 1.3B layer (~115GB total, ~7 min — downloads ~12GB models)
docker build -f Dockerfile.wanvideo-1.3b -t comfyui-wanvideo-1.3b:latest .
```

Much faster build than 14B — the diffusion model is 2.6GB instead of 28GB.

## Run (Standalone)

```bash
docker run -d \
    --runtime=nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    --network host \
    --name comfyui-session \
    comfyui-wanvideo-1.3b:latest
```

Access ComfyUI at `http://localhost:8188` once the container is healthy.

## ECR

```bash
docker tag comfyui-wanvideo-1.3b:latest 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-wanvideo-1.3b:latest
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-wanvideo-1.3b:latest
```

## References

- [Comfy-Org/Wan_2.1_ComfyUI_repackaged (HuggingFace)](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged)
- [Wan-AI/Wan2.1-T2V-1.3B (HuggingFace)](https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B)
- [kijai/ComfyUI-WanVideoWrapper (GitHub)](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [14B variant README](../job-wanvideo/README.md)
