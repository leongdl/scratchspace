# Hunyuan3D 2.1 - Image to 3D Model Generation

## Overview

Hunyuan3D 2.1 is Tencent's latest open-source 2D-to-3D generation model that converts images into high-quality 3D meshes with PBR (Physically-Based Rendering) textures.

**GitHub**: https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1

## Key Features in 2.1

- **Fully Open-Source**: Full model weights and training code released
- **PBR Texture Synthesis**: Physics-grounded material simulation
  - Metallic reflections
  - Subsurface scattering
  - Photorealistic light interaction
- **Production-Ready**: Suitable for game engines and rendering pipelines

## Model Components

| Model | Description | Parameters | HuggingFace |
|-------|-------------|------------|-------------|
| Hunyuan3D-Shape-v2-1 | Image to Shape | 3.3B | [Download](https://huggingface.co/tencent/Hunyuan3D-Shape-v2-1) |
| Hunyuan3D-Paint-v2-1 | Texture Generation | 2B | [Download](https://huggingface.co/tencent/Hunyuan3D-Paint-v2-1) |

## VRAM Requirements

| Stage | VRAM Required |
|-------|---------------|
| Shape generation only | 10GB |
| Texture generation only | 21GB |
| Shape + Texture combined | 29GB |

## AWS Instance Compatibility

| Instance | GPU | VRAM | Shape | Texture | Combined |
|----------|-----|------|-------|---------|----------|
| g5.xlarge | A10G | 24GB | ✅ | ✅ | ❌ (sequential) |
| g5.2xlarge | A10G | 24GB | ✅ | ✅ | ❌ (sequential) |
| g6.xlarge | L4 | 24GB | ✅ | ✅ | ❌ (sequential) |
| g6e.xlarge | L40S | 48GB | ✅ | ✅ | ✅ |
| p4d.24xlarge | A100 | 40GB | ✅ | ✅ | ✅ |

**G5/G6 (24GB)**: Run shape and texture in two sequential passes. Works fine, just slightly slower.

**G6e/P4d (48GB+)**: Can run full pipeline simultaneously.

## ComfyUI Integration

### Recommended: kijai/ComfyUI-Hunyuan3DWrapper
- **GitHub**: https://github.com/kijai/ComfyUI-Hunyuan3DWrapper
- Supports Hunyuan3D 2.0 and 2.1
- Good memory management

### Alternative: Yuan-ManX/ComfyUI-Hunyuan3D-2.1
- Direct 2.1 support
- Latest features

## Workflow

### Two-Stage Generation (Required for 24GB GPUs)

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Load Image  │────▶│ Hunyuan3D Shape  │────▶│ Hunyuan3D Paint  │────▶│ Save GLB    │
│             │     │ (10GB VRAM)      │     │ (21GB VRAM)      │     │             │
└─────────────┘     └──────────────────┘     └──────────────────┘     └─────────────┘
                           │                         │
                           │    Unload model         │
                           │    before next stage    │
                           └─────────────────────────┘
```

## Output

- **Format**: GLB with embedded PBR textures
- **Textures**: Albedo, Normal, Metallic, Roughness maps
- **Compatible with**: Blender, Unity, Unreal Engine, Three.js

## Example Workflow: SDXL → Multi-View → Hunyuan3D

This workflow generates an object with SDXL, creates multi-angle views, then converts to 3D:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    SDXL → Multi-View → Hunyuan3D Workflow                       │
└─────────────────────────────────────────────────────────────────────────────────┘

STAGE 1: Generate Base Image with SDXL
─────────────────────────────────────────
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Load SDXL    │────▶│ CLIP Encode  │────▶│  KSampler    │────▶│ VAE Decode   │
│ Checkpoint   │     │ (Prompt)     │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                                                      │
Prompt: "a cute robot toy, white background,                          │
         centered, product photography, 8k"                           │
                                                                      ▼
STAGE 2: Generate Multi-View Images                          ┌──────────────┐
─────────────────────────────────────────                    │ Base Image   │
                                                             └──────┬───────┘
                                                                    │
      ┌─────────────────────────────────────────────────────────────┼───────┐
      │                                                             │       │
      ▼                                                             ▼       ▼
┌──────────────┐                                          ┌──────────────────────┐
│ Zero123++    │  OR use IP-Adapter to generate           │ ImagePad / Composite │
│ Multi-View   │  multiple angles with same subject       │ (arrange views)      │
└──────────────┘                                          └──────────┬───────────┘
      │                                                              │
      │    Generates 6 views:                                        │
      │    - Front, Back, Left, Right, Top, Bottom                   │
      │                                                              │
      └──────────────────────────────────────────────────────────────┘
                                                                     │
                                                                     ▼
STAGE 3: Convert to 3D with Hunyuan3D                       ┌──────────────┐
─────────────────────────────────────────                   │ Multi-View   │
                                                            │ Image        │
                                                            └──────┬───────┘
                                                                   │
                                                                   ▼
                                                          ┌──────────────────┐
                                                          │ Hunyuan3D Shape  │
                                                          │ Generator        │
                                                          │ (10GB VRAM)      │
                                                          └────────┬─────────┘
                                                                   │
                                                                   ▼
                                                          ┌──────────────────┐
                                                          │ Hunyuan3D Paint  │
                                                          │ (Texture Gen)    │
                                                          │ (21GB VRAM)      │
                                                          └────────┬─────────┘
                                                                   │
                                                                   ▼
                                                          ┌──────────────────┐
                                                          │ Save 3D Model    │
                                                          │ (GLB with PBR)   │
                                                          └──────────────────┘
```

### Recommended Prompts for 3D-Ready Images

For best results with Hunyuan3D, generate images with:
- **White/neutral background**: "white background", "studio lighting"
- **Centered subject**: "centered", "product shot"
- **Clear object**: "single object", "isolated"
- **Good lighting**: "soft lighting", "even lighting"

Example prompt:
```
a cute robot toy, white background, centered, product photography,
studio lighting, high detail, 8k, single object
```

### Alternative: Direct Image-to-3D

If you already have a good reference image:
```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Load Image   │────▶│ Hunyuan3D Shape  │────▶│ Hunyuan3D Paint  │────▶│ Save GLB    │
└──────────────┘     └──────────────────┘     └──────────────────┘     └─────────────┘
```

## References

- [Hunyuan3D 2.1 GitHub](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1)
- [Hunyuan3D-Shape-v2-1 HuggingFace](https://huggingface.co/tencent/Hunyuan3D-Shape-v2-1)
- [Hunyuan3D-Paint-v2-1 HuggingFace](https://huggingface.co/tencent/Hunyuan3D-Paint-v2-1)
- [arXiv Paper](https://arxiv.org/abs/2506.15442)
