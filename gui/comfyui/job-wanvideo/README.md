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

## Build

```bash
# Requires base comfyui-sdxl:latest image
docker build -f Dockerfile.wanvideo -t comfyui-wanvideo:latest .
```

## Run (Standalone)

```bash
docker run --gpus all -p 8188:8188 \
    -v ./output:/opt/comfyui/output \
    comfyui-wanvideo:latest
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

## References

- [Comfy-Org/Wan_2.1_ComfyUI_repackaged (HuggingFace)](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged)
- [Wan-AI/Wan2.1-T2V-14B (HuggingFace)](https://huggingface.co/Wan-AI/Wan2.1-T2V-14B)
- [kijai/ComfyUI-WanVideoWrapper (GitHub)](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [BadAss Wan Resource List (CivitAI)](https://civitai.com/articles/16983/badass-wan-resource-list)
- [Wan-Video/Wan2.1 (GitHub)](https://github.com/Wan-Video/Wan2.1)
