# Container A: TRELLIS-2 (3D Generation + Background Removal)

## Overview

ComfyUI container optimized for 3D asset generation using Microsoft's TRELLIS-2 (4B parameters) with BRIA RMBG 1.4 for automatic background removal. Runs on port 8188.

Only one container runs at a time — swap between TRELLIS-2 and WanVideo as needed.

## Models

| Model | Source | Parameters | Size | Purpose |
|-------|--------|------------|------|---------|
| TRELLIS-2 4B | [microsoft/TRELLIS.2-4B](https://huggingface.co/microsoft/TRELLIS.2-4B) | 4B | ~6GB | Image-to-3D shape + texture generation |
| TRELLIS-image-large (ss_dec) | [microsoft/TRELLIS-image-large](https://huggingface.co/microsoft/TRELLIS-image-large) | — | ~200MB | Sparse structure decoder (auto-downloaded by node if missing) |
| DINOv3 ViT-L | [facebook/dinov3-vitl16-pretrain-lvd1689m](https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m) | — | ~1.2GB | Image feature extraction (required by TRELLIS-2) |
| BRIA RMBG 1.4 | [briaai/RMBG-1.4](https://huggingface.co/briaai/RMBG-1.4) | — | ~170MB | Background removal |

## How Models Are Loaded (Source-Verified)

Each model uses a different loading mechanism. This was verified by reading the actual node source code.

### TRELLIS-2 4B — `ComfyUI/models/microsoft/TRELLIS.2-4B/`

Source: [`ComfyUI-Trellis2/nodes.py` Trellis2LoadModel.process()](https://github.com/visualbruno/ComfyUI-Trellis2/blob/main/nodes.py)

The node constructs the path as `folder_paths.models_dir + "/microsoft/" + modelname`. If the directory doesn't exist, it calls `huggingface_hub.snapshot_download()` to download the full repo there. It then calls `Trellis2ImageTo3DPipeline.from_pretrained(model_path)` which loads individual checkpoint files as `{path}.json` + `{path}.safetensors` pairs from within that directory.

```python
# From nodes.py line ~305
download_path = os.path.join(folder_paths.models_dir, "microsoft")
model_path = os.path.join(download_path, modelname)
if not os.path.exists(model_path):
    snapshot_download(repo_id=hf_model_name, local_dir=model_path, ...)
pipeline = Trellis2ImageTo3DPipeline.from_pretrained(model_path)
```

Bake path: `/opt/comfyui/models/microsoft/TRELLIS.2-4B/`

### TRELLIS-image-large (ss_dec) — `ComfyUI/models/microsoft/TRELLIS-image-large/ckpts/`

Source: [`ComfyUI-Trellis2/nodes.py` Trellis2LoadModel.process()](https://github.com/visualbruno/ComfyUI-Trellis2/blob/main/nodes.py)

The node checks for `ss_dec_conv3d_16l8_fp16.safetensors` and its `.json` config at this exact path. If missing, it downloads both files individually via HTTP from the HuggingFace CDN.

```python
# From nodes.py line ~320
trellis_image_large_path = os.path.join(folder_paths.models_dir,
    "microsoft", "TRELLIS-image-large", "ckpts", "ss_dec_conv3d_16l8_fp16.safetensors")
```

Bake path: `/opt/comfyui/models/microsoft/TRELLIS-image-large/ckpts/`

### DINOv3 ViT-L — `ComfyUI/models/facebook/dinov3-vitl16-pretrain-lvd1689m/`

Source: [`ComfyUI-Trellis2/nodes.py` Trellis2LoadModel.process()](https://github.com/visualbruno/ComfyUI-Trellis2/blob/main/nodes.py) and [README](https://github.com/visualbruno/ComfyUI-Trellis2#readme)

The node checks for `model.safetensors` at this exact path and raises an exception if not found. It does NOT auto-download — you must clone the HF repo manually.

```python
# From nodes.py line ~318
dinov3_model_path = os.path.join(folder_paths.models_dir,
    "facebook", "dinov3-vitl16-pretrain-lvd1689m", "model.safetensors")
if not os.path.exists(dinov3_model_path):
    raise Exception("Facebook Dinov3 model not found ...")
```

Bake path: `/opt/comfyui/models/facebook/dinov3-vitl16-pretrain-lvd1689m/`

**GATED REPO WARNING**: This is a Facebook gated model on HuggingFace. Access requires:
1. A HuggingFace account
2. Requesting access at https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m
3. Waiting for **manual approval by Facebook** (not instant — can take hours/days)
4. Passing `HF_TOKEN` as a Docker build arg: `--build-arg HF_TOKEN=hf_xxx`

There is no ungated alternative — DINOv3 is architecturally required by TRELLIS-2 as its image feature extractor (`DINOv3ViTModel.from_pretrained()` in `trellis2/modules/image_feature_extractor.py`).

Fallback mirror: https://sourceforge.net/projects/dinov3.mirror/

### BRIA RMBG 1.4 — `custom_nodes/ComfyUI-BRIA_AI-RMBG/RMBG-1.4/model.pth`

Source: [`ComfyUI-BRIA_AI-RMBG/BRIA_RMBG.py` BRIA_RMBG_ModelLoader_Zho.load_model()](https://github.com/ZHO-ZHO-ZHO/ComfyUI-BRIA_AI-RMBG/blob/main/BRIA_RMBG.py)

This node loads from a hardcoded path relative to its own directory. It expects `model.pth` inside the `RMBG-1.4/` subfolder of the custom node. No HuggingFace Hub, no folder_paths — just a direct `torch.load()`.

```python
# From BRIA_RMBG.py line ~44
current_directory = os.path.dirname(os.path.abspath(__file__))
model_path = os.path.join(current_directory, "RMBG-1.4/model.pth")
net.load_state_dict(torch.load(model_path, map_location=device))
```

Bake path: `/opt/comfyui/custom_nodes/ComfyUI-BRIA_AI-RMBG/RMBG-1.4/model.pth`

Note: This is RMBG 1.4 (PyTorch `.pth`), NOT RMBG 2.0 (ONNX). The research doc referenced RMBG 2.0 but this ComfyUI node only supports 1.4.

### Weight Paths Summary

```
/opt/comfyui/
├── models/
│   ├── microsoft/
│   │   ├── TRELLIS.2-4B/                              # snapshot_download from HF
│   │   │   └── ckpts/*.safetensors + *.json
│   │   └── TRELLIS-image-large/
│   │       └── ckpts/
│   │           ├── ss_dec_conv3d_16l8_fp16.safetensors
│   │           └── ss_dec_conv3d_16l8_fp16.json
│   └── facebook/
│       └── dinov3-vitl16-pretrain-lvd1689m/
│           └── model.safetensors                       # must exist or node raises
└── custom_nodes/
    └── ComfyUI-BRIA_AI-RMBG/
        └── RMBG-1.4/
            └── model.pth                               # hardcoded relative path
```

## Custom Nodes

| Node | Repository | Purpose |
|------|------------|---------|
| ComfyUI-BRIA_AI-RMBG | [ZHO-ZHO-ZHO/ComfyUI-BRIA_AI-RMBG](https://github.com/ZHO-ZHO-ZHO/ComfyUI-BRIA_AI-RMBG) | Background removal (RMBG 1.4) |
| ComfyUI-Trellis2 | [visualbruno/ComfyUI-Trellis2](https://github.com/visualbruno/ComfyUI-Trellis2) | TRELLIS-2 3D generation wrapper |

## Dependencies

- `xformers==0.0.30` (default attention backend, must be pinned to match torch 2.7.0)
- Pre-built wheels from `ComfyUI-Trellis2/wheels/Linux/Torch270/` (cumesh, nvdiffrast, flex_gemm, o_voxel)
  - Must install with `pip install --no-deps` because o_voxel declares cumesh as a git dependency which conflicts with the local wheel
- `requirements.txt` from both custom node repos
- PyTorch 2.7.0+cu126 (the wheels require torch 2.7.0; cu126 requires CUDA 12.6 base image)

**Standalone image required**: Cannot layer on `comfyui-sdxl:latest` (torch 2.6.0+cu124) because:
- Trellis2 wheels require torch 2.7.0, which is not available for cu124
- torch 2.7.0+cu126 on a cu124 base causes `undefined symbol: cudaGetDriverEntryPointByVersion`
- Uses `nvidia/cuda:12.6.3-devel-rockylinux9` as base instead

Source: [ComfyUI-Trellis2 Installation Guide](https://github.com/visualbruno/ComfyUI-Trellis2#%EF%B8%8F-installation-guide)

## VRAM Requirements

| Operation | VRAM |
|-----------|------|
| RMBG 1.4 inference | ~1GB |
| TRELLIS-2 4B generation (1536³) | ~24GB |
| Combined pipeline | ~24GB |

TRELLIS-2 4B is the largest available variant. At 1536³ resolution it uses ~24GB, fitting well within the 48GB L40S.

Source: [TRELLIS.2-4B HuggingFace — Requirements](https://huggingface.co/microsoft/TRELLIS.2-4B)

## Hardware Target

| Instance | GPU | VRAM | Status |
|----------|-----|------|--------|
| g6e.xlarge | L40S | 48GB | ✅ Primary target |
| p4d.24xlarge | A100 | 40GB | ✅ |
| g5.xlarge | A10G | 24GB | ✅ (1024³ max) |
| g6.xlarge | L4 | 24GB | ✅ (1024³ max) |

## Build

```bash
# Standalone image (does NOT require comfyui-sdxl base)
# HF_TOKEN required for gated DINOv3 model
docker build --build-arg HF_TOKEN=hf_xxx -f Dockerfile.trellis2 -t comfyui-trellis2:latest .
```

## Run (Standalone)

```bash
docker run --gpus all -p 8188:8188 \
    -v ./output:/opt/comfyui/output \
    comfyui-trellis2:latest
```

## Pipeline

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Load Image   │────▶│ RMBG 1.4         │────▶│ TRELLIS-2 4B     │────▶│ Save GLB    │
│              │     │ (bg removal)     │     │ (3D generation)  │     │             │
└──────────────┘     └──────────────────┘     └──────────────────┘     └─────────────┘
```

## Network

- Port: `8188`
- Only one container runs at a time — swap between TRELLIS-2 and WanVideo as needed

## ECR

```bash
docker tag comfyui-trellis2:latest 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-trellis2:latest
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-trellis2:latest
```

## References

- [TRELLIS.2-4B HuggingFace](https://huggingface.co/microsoft/TRELLIS.2-4B)
- [TRELLIS-image-large HuggingFace](https://huggingface.co/microsoft/TRELLIS-image-large)
- [DINOv3 ViT-L HuggingFace](https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m)
- [BRIA RMBG 1.4 HuggingFace](https://huggingface.co/briaai/RMBG-1.4)
- [ComfyUI-Trellis2 GitHub](https://github.com/visualbruno/ComfyUI-Trellis2)
- [ComfyUI-BRIA_AI-RMBG GitHub](https://github.com/ZHO-ZHO-ZHO/ComfyUI-BRIA_AI-RMBG)
- [TRELLIS.2 Paper (arXiv)](https://arxiv.org/abs/2512.14692)
- [TRELLIS.2 Project Page](https://microsoft.github.io/TRELLIS.2/)
