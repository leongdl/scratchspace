# Hunyuan3D ComfyUI Workflow Guide

## Stage 1: Image Creation (SDXL)

Create a high-quality 2D image that will become your 3D model.

### Nodes to add:
1. **Load Checkpoint**
2. **CLIP Text Encode** (for positive prompt)
3. **CLIP Text Encode** (for negative prompt) 
4. **Empty Latent Image**
5. **KSampler**
6. **VAE Decode**

### Connections:

| From Node | Output | → | To Node | Input |
|-----------|--------|---|---------|-------|
| Load Checkpoint | MODEL | → | KSampler | model |
| Load Checkpoint | CLIP | → | CLIP Text Encode (positive) | clip |
| Load Checkpoint | CLIP | → | CLIP Text Encode (negative) | clip |
| Load Checkpoint | VAE | → | VAE Decode | vae |
| CLIP Text Encode (positive) | CONDITIONING | → | KSampler | positive |
| CLIP Text Encode (negative) | CONDITIONING | → | KSampler | negative |
| Empty Latent Image | LATENT | → | KSampler | latent_image |
| KSampler | LATENT | → | VAE Decode | samples |

### Settings:
- Load Checkpoint: Select `sd_xl_base_1.0.safetensors`
- Empty Latent Image: 1024x1024
- KSampler: steps=20, cfg=7, sampler=euler, scheduler=normal

---

## Stage 2: Multi-View Generation

Generate views from multiple angles (front, side, back).

### Nodes to add:
1. **Hy3D_MultiView_Gen** (or similar name in Hunyuan3D category)

### Connections:

| From Node | Output | → | To Node | Input |
|-----------|--------|---|---------|-------|
| VAE Decode | IMAGE | → | Hy3D_MultiView_Gen | image |

---

## Stage 3: 3D Mesh Generation

Convert the multi-view images into a 3D mesh.

### Nodes to add:
1. **Hy3DModelLoader** (loads the shape generation model)
2. **Hy3D_Mesh_Gen** (generates the mesh)
3. **Save 3D Mesh** (exports .obj/.glb file)

### Connections:

| From Node | Output | → | To Node | Input |
|-----------|--------|---|---------|-------|
| Hy3DModelLoader | MODEL | → | Hy3D_Mesh_Gen | model |
| Hy3D_MultiView_Gen | IMAGE | → | Hy3D_Mesh_Gen | images |
| Hy3D_Mesh_Gen | MESH | → | Save 3D Mesh | mesh |

### Settings:
- Hy3DModelLoader: Select the dit model (hunyuan3d-dit-v2-1)

---

## Stage 4: Texture & Material Painting

Apply PBR textures to the 3D mesh.

### Nodes to add:
1. **Hy3D_Paint** (applies textures)
2. **Save Image** (for texture maps)
3. **Save Material File** (for .mtl file, if available)

### Connections:

| From Node | Output | → | To Node | Input |
|-----------|--------|---|---------|-------|
| Hy3D_Mesh_Gen | MESH | → | Hy3D_Paint | mesh |
| Hy3D_MultiView_Gen | IMAGE | → | Hy3D_Paint | images |
| Hy3D_Paint | TEXTURE | → | Save Image | images |
| Hy3D_Paint | MATERIAL | → | Save Material File | mtl |

---

## Complete Flow Diagram

```
[Load Checkpoint]
    ├── MODEL → [KSampler]
    ├── CLIP → [CLIP Text Encode +] → positive → [KSampler]
    ├── CLIP → [CLIP Text Encode -] → negative → [KSampler]
    └── VAE → [VAE Decode]

[Empty Latent Image] → latent_image → [KSampler]

[KSampler] → LATENT → [VAE Decode] → IMAGE → [Hy3D_MultiView_Gen]
                                                    │
                                                    ├── IMAGE → [Hy3D_Mesh_Gen] → MESH → [Save 3D Mesh]
                                                    │                │
                                                    │                └── MESH ─┐
                                                    │                          │
                                                    └── IMAGE ────────────────→ [Hy3D_Paint]
                                                                                    │
                                                                                    ├── TEXTURE → [Save Image]
                                                                                    └── MATERIAL → [Save Material]

[Hy3DModelLoader] → MODEL → [Hy3D_Mesh_Gen]
```

---

## VRAM Requirements

| Stage | VRAM Needed |
|-------|-------------|
| Stage 1 (SDXL) | ~8GB |
| Stage 2 (MultiView) | ~6GB |
| Stage 3 (Mesh Gen) | ~10GB |
| Stage 4 (Paint) | ~21GB |
| **All at once** | **~29GB** |

Tip: Run stages sequentially on 24GB GPUs, or use 48GB+ for full pipeline.

---

## Tips

1. **Test Stage 1 first** - Make sure your SDXL image looks good before generating 3D
2. **Check node names** - The exact names may vary (look in the Hunyuan3D node category)
3. **Save intermediate outputs** - Add Preview Image nodes between stages to check progress
4. **Iterate on shape first** - If the mesh looks good but colors are off, only re-run Stage 4
