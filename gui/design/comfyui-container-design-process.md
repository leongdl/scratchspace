# ComfyUI Container Design Process: Research-to-README Methodology

## Purpose

This document captures the systematic approach used to design Docker containers for ComfyUI custom nodes (TRELLIS-2, WanVideo). The process starts from rough architectural notes, validates assumptions against actual source code, and produces accurate build-ready READMEs. This methodology is reusable as a skill/power for any ComfyUI node containerization task.

## The Problem

AI model containers fail at runtime because:
- Research docs and blog posts describe model paths that don't match how ComfyUI nodes actually load weights
- Different nodes use different loading mechanisms (folder_paths, from_pretrained, hardcoded relative paths, HuggingFace Hub cache)
- Baking weights into the wrong directory means the node can't find them, causing either silent re-downloads or crashes

## Process Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ 1. Gather       │────▶│ 2. Read Existing │────▶│ 3. Clone & Read │────▶│ 4. Write        │
│    Starting     │     │    Patterns      │     │    Node Source   │     │    Verified     │
│    Data         │     │                  │     │    Code          │     │    README        │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Step 1: Gather Starting Data

Collect the initial architectural intent from whatever source is available:
- Research notes, design docs, chat transcripts, Gemini/ChatGPT shares
- HuggingFace model cards
- Blog posts, tutorials, CivitAI articles
- Existing Dockerfiles in the project

What to extract:
- Model names and HuggingFace repo IDs
- Custom node GitHub repos
- Target hardware (GPU, VRAM)
- Port assignments and container topology
- Any weight download URLs mentioned

In our case, the starting data was `gui/reseearch/trellias.md` which described a dual-container architecture with TRELLIS-2 and WanVideo. It included draft Dockerfiles with `wget` commands pointing to specific HuggingFace URLs.

## Step 2: Read Existing Patterns

Before designing new containers, read the existing project conventions:
- Base Dockerfile (`gui/comfyui/Dockerfile`) — OS, Python version, CUDA version, user setup
- Derivative Dockerfiles (`Dockerfile.sdxl`, `Dockerfile.flux`, `Dockerfile.hunyuan3d`) — layering pattern, FROM base, weight download approach
- Job templates (`job/template.yaml`) — ECR registry, parameter structure
- Build scripts (`build.sh`) — tagging conventions
- ComfyUI's `folder_paths.py` — the canonical model path registry

Key things to note from `folder_paths.py`:
```python
models_dir = os.path.join(base_path, "models")
folder_names_and_paths["diffusion_models"] = ([
    os.path.join(models_dir, "unet"),
    os.path.join(models_dir, "diffusion_models")
], supported_pt_extensions)
folder_names_and_paths["vae"] = ([os.path.join(models_dir, "vae")], ...)
folder_names_and_paths["text_encoders"] = ([
    os.path.join(models_dir, "text_encoders"),
    os.path.join(models_dir, "clip")
], ...)
```

This tells you where standard ComfyUI nodes look for models. But custom nodes may NOT use this system.

## Step 3: Clone and Read Node Source Code

This is the critical step that most people skip. Clone each custom node repo and read the actual model loading code.

```bash
git clone --depth 1 https://github.com/<org>/<repo>.git custom_nodes/<repo>
```

For each node, find the model loading class and answer:
1. Does it use `folder_paths.get_filename_list()` / `folder_paths.get_full_path_or_raise()`? → Standard ComfyUI path
2. Does it use `huggingface_hub.snapshot_download()` or `hf_hub_download()`? → HF cache or custom local_dir
3. Does it use `from_pretrained(repo_id)`? → HF cache (`~/.cache/huggingface/hub/`)
4. Does it use hardcoded `os.path.join(current_directory, ...)`? → Relative to the node's own directory
5. Does it construct paths from `folder_paths.models_dir` directly? → Custom subdirectory under models/

### What We Found

| Node | Loading Mechanism | Path |
|------|-------------------|------|
| ComfyUI-WanVideoWrapper (diffusion) | `folder_paths.get_full_path_or_raise("diffusion_models", model)` | `models/diffusion_models/` ✅ standard |
| ComfyUI-WanVideoWrapper (VAE) | `folder_paths.get_full_path_or_raise("vae", model_name)` | `models/vae/` ✅ standard |
| ComfyUI-WanVideoWrapper (T5) | `folder_paths.get_full_path_or_raise("text_encoders", model_name)` | `models/text_encoders/` ✅ standard |
| ComfyUI-Trellis2 (TRELLIS-2) | `snapshot_download()` → `Trellis2ImageTo3DPipeline.from_pretrained(local_path)` | `models/microsoft/TRELLIS.2-4B/` ⚠️ custom |
| ComfyUI-Trellis2 (DINOv3) | `os.path.join(folder_paths.models_dir, "facebook", ...)` with hard raise | `models/facebook/dinov3-vitl16-pretrain-lvd1689m/` ⚠️ custom, mandatory |
| ComfyUI-Trellis2 (ss_dec) | Direct HTTP download to `models/microsoft/TRELLIS-image-large/ckpts/` | Auto-downloads if missing |
| ComfyUI-BRIA_AI-RMBG | `os.path.join(current_directory, "RMBG-1.4/model.pth")` | `custom_nodes/ComfyUI-BRIA_AI-RMBG/RMBG-1.4/model.pth` ⚠️ hardcoded |

### Discrepancies Found vs Research Doc

| Research Doc Claimed | Actual (Source-Verified) |
|---------------------|--------------------------|
| RMBG 2.0 ONNX at `models/onnx/rmbg_2.0.onnx` | RMBG 1.4 PyTorch at `custom_nodes/.../RMBG-1.4/model.pth` |
| TRELLIS weights at `models/trellis2/ckpts/` via wget | `models/microsoft/TRELLIS.2-4B/` via snapshot_download |
| No mention of DINOv3 | Required, raises exception if missing |
| No mention of TRELLIS-image-large ss_dec | Required, auto-downloads if missing |

## Step 4: Write Verified README

Structure the README with these sections:

1. **Overview** — what the container does, port, one-at-a-time vs concurrent
2. **Models table** — name, HuggingFace source, parameters, size, purpose
3. **How Models Are Loaded (Source-Verified)** — for each model:
   - Which source file and class/method does the loading
   - Link to the GitHub source
   - The actual Python code snippet showing path construction
   - The resulting bake path for the Dockerfile
4. **Weight Paths Summary** — ASCII tree of all paths
5. **Custom Nodes** — repo links
6. **Dependencies** — special build requirements (wheels, flash-attn, etc.)
7. **VRAM Requirements** — per-operation breakdown
8. **Hardware Target** — instance compatibility matrix
9. **Build / Run / ECR** — copy-paste commands
10. **References** — all URLs used during research

## Applying This as a Skill

When asked to containerize a new ComfyUI node:

```
INPUT:  Model name, HuggingFace repo, ComfyUI custom node repo
OUTPUT: README with verified model paths, Dockerfile

STEPS:
1. Clone the custom node repo
2. Find the model loader class (search for folder_paths, from_pretrained, load_state_dict, snapshot_download)
3. Trace the path construction to determine exact filesystem location
4. Cross-reference with ComfyUI's folder_paths.py for standard vs custom paths
5. Document each model's loading mechanism with source code snippets
6. Produce the README, then the Dockerfile
```

Key grep patterns to find model loading in custom nodes:
```bash
grep -rn "folder_paths" nodes.py
grep -rn "from_pretrained" nodes.py
grep -rn "snapshot_download" nodes.py
grep -rn "hf_hub_download" nodes.py
grep -rn "load_state_dict" nodes.py
grep -rn "torch.load" *.py
grep -rn "models_dir" nodes.py
```

## Files Produced

| File | Purpose |
|------|---------|
| `gui/comfyui/job-trellis2/README.md` | TRELLIS-2 container design with source-verified model paths |
| `gui/comfyui/job-wanvideo/README.md` | WanVideo container design with source-verified model paths |
| `gui/comfyui/Dockerfile.trellis2` | (pending) Dockerfile for TRELLIS-2 container |
| `gui/comfyui/Dockerfile.wanvideo` | (pending) Dockerfile for WanVideo container |
