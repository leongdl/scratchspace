# Hunyuan3D ComfyUI Workflow Guide

Based on kijai's ComfyUI-Hunyuan3DWrapper nodes.

## Quick Start: Single-View Image to 3D

This is the simplest workflow - one image in, 3D model out.

### Nodes Required:
1. **Load Image** - Your input image
2. **Hy3DModelLoader** - Loads the shape generation model
3. **Hy3DGenerateMesh** - Generates 3D mesh from image
4. **Preview3D** or **Save 3D Mesh** - View/save result

### Connections:

| From Node | Output | → | To Node | Input |
|-----------|--------|---|---------|-------|
| Load Image | IMAGE | → | Hy3DGenerateMesh | image |
| Hy3DModelLoader | MODEL | → | Hy3DGenerateMesh | model |
| Hy3DModelLoader | VAE | → | Hy3DGenerateMesh | vae |
| Hy3DGenerateMesh | MESH | → | Preview3D / Save 3D Mesh | mesh |

### Settings:
- **Hy3DModelLoader**: Select `hunyuan3d-dit-v2-0-fp16.safetensors` or `hunyuan3d-dit-v2-1`
- Model path: `ComfyUI/models/diffusion_models/`

---

## Full Workflow: Image to Textured 3D Model

### Stage 1: Load Models

| Node | Purpose |
|------|---------|
| **Hy3DModelLoader** | Loads shape generation model (DiT + VAE) |

### Stage 2: Generate Mesh

| Node | Purpose |
|------|---------|
| **Load Image** | Input image (ideally with transparent/removed background) |
| **Hy3DGenerateMesh** | Converts image to 3D mesh |

### Connections:

| From | Output | → | To | Input |
|------|--------|---|-----|-------|
| Load Image | IMAGE | → | Hy3DGenerateMesh | image |
| Hy3DModelLoader | MODEL | → | Hy3DGenerateMesh | model |
| Hy3DModelLoader | VAE | → | Hy3DGenerateMesh | vae |

### Stage 3: Generate Texture (Optional)

For textured output, add texture generation nodes:

| Node | Purpose |
|------|---------|
| **Hy3DTextureGen** | Generates PBR textures for the mesh |

| From | Output | → | To | Input |
|------|--------|---|-----|-------|
| Hy3DGenerateMesh | MESH | → | Hy3DTextureGen | mesh |
| Load Image | IMAGE | → | Hy3DTextureGen | image |

### Stage 4: Save Output

| Node | Purpose |
|------|---------|
| **Preview3D** | Preview in ComfyUI |
| **Save 3D Mesh** | Export .obj/.glb file |

---

## Multi-View Workflow (Better Quality)

Use multiple views for higher quality 3D generation.

### Nodes:
1. **Load Image** (x4) - Front, Left, Back, Right views
2. **Hy3DModelLoader** - Use `hunyuan3d-dit-v2-mv` model
3. **Hy3DGenerateMeshMultiView** - Multi-view mesh generation

### Connections:

| From | Output | → | To | Input |
|------|--------|---|-----|-------|
| Load Image (front) | IMAGE | → | Hy3DGenerateMeshMultiView | front |
| Load Image (left) | IMAGE | → | Hy3DGenerateMeshMultiView | left |
| Load Image (back) | IMAGE | → | Hy3DGenerateMeshMultiView | back |
| Load Image (right) | IMAGE | → | Hy3DGenerateMeshMultiView | right |
| Hy3DModelLoader | MODEL | → | Hy3DGenerateMeshMultiView | model |
| Hy3DModelLoader | VAE | → | Hy3DGenerateMeshMultiView | vae |

---

## Complete Flow Diagram

```
[Load Image] ─────────────────────────────────────┐
                                                  │
[Hy3DModelLoader]                                 │
    ├── MODEL ──┐                                 │
    └── VAE ────┼──→ [Hy3DGenerateMesh] ←─────────┘
                │           │
                │           ├── MESH ──→ [Preview3D]
                │           │
                │           └── MESH ──→ [Hy3DTextureGen] ──→ [Save Image]
                │                              ↑
[Load Image] ──────────────────────────────────┘
```

---

## Model Files Location

Models should be in `ComfyUI/models/diffusion_models/`:
- `hunyuan3d-dit-v2-0-fp16.safetensors` (single-view)
- `hunyuan3d-dit-v2-1.safetensors` (v2.1)
- `hunyuan3d-dit-v2-mv.safetensors` (multi-view)
- `hunyuan3d-dit-v2-mv-turbo.safetensors` (fast multi-view)

Pre-baked models in this container are at `/opt/hunyuan3d-models/`

---

## VRAM Requirements

| Operation | VRAM |
|-----------|------|
| Shape generation (single-view) | ~10GB |
| Shape generation (multi-view) | ~12GB |
| Texture generation | ~21GB |
| Full pipeline | ~29GB |

**Tip:** On 24GB GPUs, run shape and texture generation separately.

---

## Tips

1. **Remove background first** - Use rembg or similar before feeding to Hy3D nodes
2. **Check node names** - Right-click canvas → Add Node → Search "Hy3D"
3. **Start simple** - Test with just Hy3DModelLoader + Hy3DGenerateMesh + Preview3D
4. **Use turbo model** - `hunyuan3d-dit-v2-mv-turbo` is faster for testing
