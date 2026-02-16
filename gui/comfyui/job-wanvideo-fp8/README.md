# Container: WanVideo 2.1 T2V 14B fp8 (Quantized AI Video Generation)

## Overview

ComfyUI container for AI video generation using the Wan 2.1 T2V 14B model quantized to fp8. Same 14B architecture as the fp16 variant but half the file size and ~half the VRAM. Minimal quality loss. All weights are baked into the container. Runs on port 8188.

## Models

| Model | Source | Size | Purpose |
|-------|--------|------|---------|
| Wan 2.1 T2V 14B fp8_scaled | [Comfy-Org](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/diffusion_models/wan2.1_t2v_14B_fp8_scaled.safetensors) | ~13.3GB | Text-to-video diffusion model (quantized) |
| Wan 2.1 VAE | [Comfy-Org](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/vae/wan_2.1_vae.safetensors) | ~300MB | Video VAE decoder |
| UMT5-XXL fp16 | [Comfy-Org](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/blob/main/split_files/text_encoders/umt5_xxl_fp16.safetensors) | ~10.6GB | Text encoder (fp16 — fp8_scaled not supported by WanVideoWrapper) |

## Variant Comparison

| Aspect | 14B fp16 | 14B fp8 (this) | 1.3B fp16 |
|--------|----------|----------------|-----------|
| Diffusion model | 26.6GB | 13.3GB | 2.6GB |
| Text encoder | 10.6GB (fp16) | 10.6GB (fp16) | 10.6GB (fp16) |
| Total new data | ~38GB | ~24GB | ~13GB |
| VRAM required | ~40GB | ~20-24GB | ~8GB |
| Min GPU | L40S 48GB | L4 24GB | L4 24GB |
| Quality | Best | Near-best | Lower |
| RAM swap needed | Yes (≤32GB) | No | No |

Quality rank for fp8 variants: fp8_scaled (used here) > fp8_e4m3fn.

## Weight Paths

```
/opt/comfyui/models/
├── diffusion_models/
│   └── wan2.1_t2v_14B_fp8_scaled.safetensors       # 13.3GB
├── vae/
│   └── wan_2.1_vae.safetensors                      # 300MB
└── text_encoders/
    └── umt5_xxl_fp16.safetensors                    # 10.6GB
```

Same `folder_paths` loading as the fp16 variant — see `job-wanvideo/README.md` for source-verified details.

## VRAM Requirements

| Operation | VRAM |
|-----------|------|
| Wan 2.1 14B fp8 inference | ~20-24GB |
| UMT5-XXL fp16 text encoding | ~10GB (offloaded after encoding) |

Fits on 24GB GPUs. No swap file needed on instances with ≥16GB RAM.

## Hardware Target

| Instance | GPU | VRAM | RAM | Status |
|----------|-----|------|-----|--------|
| g6.xlarge | L4 | 24GB | 16GB | ✅ Primary target |
| g5.xlarge | A10G | 24GB | 16GB | ✅ |
| g6e.xlarge | L40S | 48GB | 30GB | ✅ Plenty of headroom |

## Build

```bash
cd gui/comfyui

# 1. Base image (~19GB, ~5 min)
docker build -t comfyui-rocky:latest .

# 2. SDXL layer (~46GB total, ~5 min)
docker build -f Dockerfile.sdxl -t comfyui-sdxl:latest .

# 3. WanVideo fp8 layer (~20GB new data, ~8 min)
docker build -f Dockerfile.wanvideo-fp8 -t comfyui-wanvideo-fp8:latest .
```

Faster build than fp16 — downloads ~20GB instead of ~38GB.

## Run (Standalone)

```bash
docker run -d \
    --runtime=nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    --network host \
    --name comfyui-session \
    comfyui-wanvideo-fp8:latest
```

Access ComfyUI at `http://localhost:8188`.

## ECR

```bash
docker tag comfyui-wanvideo-fp8:latest 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-wanvideo-fp8:latest
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-wanvideo-fp8:latest
```

## References

- [Comfy-Org/Wan_2.1_ComfyUI_repackaged (HuggingFace)](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged)
- [14B fp16 variant README](../job-wanvideo/README.md)
- [1.3B variant README](../job-wanvideo-1.3b/README.md)
