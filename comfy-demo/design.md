# comfy-gui: Wan 2.2 S2V Audio-Driven Video Container

Container design for running the `comfy-dag.json` workflow — a Wan 2.2 Speech-to-Video (S2V) pipeline with audio-driven lip-sync, multi-chunk extend, and LightX2V 4-step LoRA acceleration.

## Workflow Analysis (comfy-dag.json)

The DAG is a Wan 2.2 S2V 14B pipeline that:

1. Loads a reference image + audio clip
2. Encodes audio via wav2vec2
3. Runs an initial KSampler pass (basic sampling)
4. Extends the video in 77-frame chunks via "Video S2V Extend" subgraphs (x2 in the DAG)
5. Fixes the overbaked first frame (LatentCut/LatentConcat hack)
6. Decodes via VAE and saves as MP4

The workflow has two parallel tracks (duplicated node groups at y=0 and y=1680) — likely for A/B comparison or batch variation. Both tracks share the same models.

### Node Types Used

All nodes are `comfy-core` (v0.3.54) — no third-party custom nodes required:

| Node | Purpose |
|------|---------|
| UNETLoader | Loads wan2.2_s2v_14B diffusion model |
| CLIPLoader | Loads umt5_xxl text encoder |
| VAELoader | Loads wan_2.1_vae |
| AudioEncoderLoader | Loads wav2vec2 audio encoder |
| LoraLoaderModelOnly | Applies LightX2V 4-step LoRA |
| ModelSamplingSD3 | Sets shift=8 for Wan sampling schedule |
| CLIPTextEncode | Positive/negative prompts |
| KSampler | Initial video sampling |
| AudioEncoderEncode | Encodes audio for conditioning |
| LoadImage | Reference image input |
| LoadAudio | Audio clip input |
| Video S2V Extend (subgraph) | 77-frame chunk extension (x2) |
| LatentCut / LatentConcat | First-frame fix hack |
| VAEDecode | Latent → frames |
| ImageFromBatch | Extract frame range |
| CreateVideo / SaveVideo | Assemble + save MP4 |
| PrimitiveInt / PrimitiveFloat | Shared parameters (steps, cfg, chunk length, batch size) |

## Models to Bake

Five model files extracted from the DAG's `"models"` metadata (deduplicated):

| Model | File | Directory | Size (est.) | Source |
|-------|------|-----------|-------------|--------|
| Wan 2.2 S2V 14B fp8 | `wan2.2_s2v_14B_fp8_scaled.safetensors` | `diffusion_models/` | ~13.3GB | [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_s2v_14B_fp8_scaled.safetensors) |
| UMT5-XXL fp8 | `umt5_xxl_fp8_e4m3fn_scaled.safetensors` | `text_encoders/` | ~5.3GB | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors) |
| Wan 2.1 VAE | `wan_2.1_vae.safetensors` | `vae/` | ~300MB | [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors) |
| wav2vec2 Audio Encoder | `wav2vec2_large_english_fp16.safetensors` | `audio_encoders/` | ~1.2GB | [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/audio_encoders/wav2vec2_large_english_fp16.safetensors) |
| LightX2V 4-step LoRA | `wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors` | `loras/` | ~200MB | [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors) |

Total baked model data: ~20GB

Plus preview decoder:
| TAESD Wan 2.1 | `taew2_1.safetensors` | `vae_approx/` | ~5MB | [Kijai/WanVideo_comfy](https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/taew2_1.safetensors) |

### Key Differences from Existing WanVideo Containers

| Aspect | Existing (Dockerfile.wanvideo*) | This (comfy-gui) |
|--------|--------------------------------|-------------------|
| Model variant | Wan 2.1 T2V (text-to-video) | Wan 2.2 S2V (speech-to-video) |
| Diffusion model | wan2.1_t2v_14B_fp16/fp8 | wan2.2_s2v_14B_fp8_scaled |
| Text encoder | umt5_xxl_fp16 (10.6GB) | umt5_xxl_fp8_e4m3fn_scaled (5.3GB) |
| Audio encoder | Not needed | wav2vec2_large_english_fp16 (new) |
| LoRA | None | LightX2V 4-step acceleration |
| Custom nodes | ComfyUI-WanVideoWrapper | None (all comfy-core) |
| Audio directory | N/A | `audio_encoders/` (new) |

The DAG uses native ComfyUI core nodes (v0.3.54+) for Wan 2.2 S2V — no WanVideoWrapper needed. This is a newer ComfyUI feature where S2V support was added directly to core.

## Container Design

### Image Layering

```
comfyui-rocky:latest          (base: Rocky 9 + CUDA 12.4 + Python 3.12 + ComfyUI + torch)
  └── comfyui-sdxl:latest     (+ SDXL checkpoints, shared base for all variants)
        └── comfyui-wan22-s2v:latest   (+ Wan 2.2 S2V models, this container)
```

Layers on `comfyui-sdxl:latest` like the existing wanvideo containers. No custom nodes to install, no native CUDA extensions — pure model downloads.

### Dockerfile Plan (Dockerfile.wan22-s2v)

```
FROM comfyui-sdxl:latest

# Create model directories (audio_encoders is new)
mkdir -p diffusion_models/ text_encoders/ audio_encoders/ loras/

# Bake 5 models:
# 1. wan2.2_s2v_14B_fp8_scaled.safetensors → diffusion_models/  (~13.3GB)
# 2. umt5_xxl_fp8_e4m3fn_scaled.safetensors → text_encoders/    (~5.3GB)
# 3. wan_2.1_vae.safetensors → vae/                              (~300MB)
# 4. wav2vec2_large_english_fp16.safetensors → audio_encoders/   (~1.2GB)
# 5. wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors → loras/ (~200MB)
# 6. taew2_1.safetensors → vae_approx/                           (~5MB)

# No custom nodes needed — all nodes are comfy-core
# No pip installs needed beyond base
```

### VRAM / Hardware Requirements

The DAG uses fp8_scaled for both the diffusion model and text encoder, keeping VRAM low:

| Component | VRAM |
|-----------|------|
| Wan 2.2 S2V 14B fp8 inference | ~20-24GB |
| UMT5-XXL fp8 text encoding | ~5GB (offloaded after encoding) |
| wav2vec2 audio encoding | ~1GB (offloaded after encoding) |
| VAE decode | ~2GB |

Estimated peak VRAM: ~24-28GB (during diffusion sampling with conditioning)

| Instance | GPU | VRAM | RAM | Status |
|----------|-----|------|-----|--------|
| g6e.xlarge | L40S | 48GB | 30GB | ✅ Primary target (plenty of headroom) |
| g6e.2xlarge | L40S | 48GB | 64GB | ✅ |
| g5.xlarge | A10G | 24GB | 16GB | ⚠️ Tight — may work with --disable-smart-memory |
| g6.xlarge | L4 | 24GB | 16GB | ⚠️ Tight — may work with --disable-smart-memory |

The fp8 quantization makes this much more accessible than the fp16 wanvideo variants. The LightX2V LoRA reduces steps from ~30 to ~10, cutting generation time significantly.

### Estimated Image Size

| Layer | Size |
|-------|------|
| comfyui-sdxl:latest (inherited) | ~46GB |
| wan2.2_s2v_14B_fp8_scaled | ~13.3GB |
| umt5_xxl_fp8_e4m3fn_scaled | ~5.3GB |
| wan_2.1_vae | ~300MB |
| wav2vec2_large_english_fp16 | ~1.2GB |
| LightX2V LoRA | ~200MB |
| chown layer | metadata only |
| **Total** | **~66GB** |

Significantly smaller than the fp16 wanvideo image (~140GB).

## Folder Structure

```
comfy-gui/
├── design.md                    # This file
├── Dockerfile.wan22-s2v         # Container definition
├── README.md                    # Build/run/deploy docs
└── job/
    ├── template.yaml            # Deadline Cloud job template
    └── submit.sh                # Job submission script
```

## Pipeline Diagram

```
┌────────────┐  ┌────────────┐
│ LoadImage   │  │ LoadAudio  │
│ (ref face)  │  │ (speech)   │
└──────┬──────┘  └──────┬─────┘
       │                │
       │         ┌──────▼──────┐
       │         │AudioEncoder │
       │         │  Encode     │
       │         └──────┬──────┘
       │                │
┌──────▼──────┐  ┌──────▼──────┐  ┌──────────────┐
│ UNETLoader  │  │ CLIPLoader  │  │ VAELoader    │
│ (S2V 14B    │  │ (UMT5-XXL   │  │ (Wan 2.1)    │
│  fp8)       │  │  fp8)       │  │              │
└──────┬──────┘  └──────┬──────┘  └──────┬───────┘
       │                │                │
┌──────▼──────┐         │                │
│ LoraLoader  │         │                │
│ (LightX2V   │         │                │
│  4-step)    │         │                │
└──────┬──────┘         │                │
       │                │                │
┌──────▼────────────────▼────────────────▼───────┐
│              KSampler (initial)                 │
│              shift=8, steps=10, cfg=6           │
└──────────────────────┬─────────────────────────┘
                       │
              ┌────────▼────────┐
              │ Video S2V       │  x2 (77 frames each)
              │ Extend          │
              │ (subgraph)      │
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │ Fix overbaked   │
              │ first frame     │
              │ (LatentCut +    │
              │  LatentConcat)  │
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │ VAEDecode →     │
              │ CreateVideo →   │
              │ SaveVideo (MP4) │
              └─────────────────┘
```

## Build & Run

```bash
cd gui/comfyui

# 1. Base + SDXL (if not already built)
docker build -t comfyui-rocky:latest .
docker build -f Dockerfile.sdxl -t comfyui-sdxl:latest .

# 2. Wan 2.2 S2V
docker build -f ../comfy-gui/Dockerfile.wan22-s2v -t comfyui-wan22-s2v:latest .

# 3. Run
docker run -d \
    --runtime=nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    --network host \
    --name comfyui-session \
    comfyui-wan22-s2v:latest
```

## ComfyUI Version Requirement

The DAG uses native Wan 2.2 S2V nodes (`AudioEncoderLoader`, `AudioEncoderEncode`, and the S2V subgraph components) which were added in ComfyUI core v0.3.54. The base `comfyui-rocky` Dockerfile clones `latest` from GitHub, which should include these. If the base image was built before these nodes were added, it needs to be rebuilt.

## Open Questions

1. The DAG has a second UNETLoader (node 161, mode=4/muted) — this appears to be a disabled alternate model slot. We only need to bake the active one.
2. The `audio_encoders/` directory is new to this workflow — verify ComfyUI's `folder_paths` includes it by default in v0.3.54+.
3. The LightX2V LoRA is labeled `t2v` but applied to the S2V model — confirm compatibility (likely fine since S2V shares the T2V backbone).
