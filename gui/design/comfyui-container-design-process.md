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

## Step 3b: Verify Weights Are Baked After Build

After `docker build` completes, verify the model weights are actually present in the image. The image may be too large for `docker run` to start quickly, so use `docker history` instead:

```bash
docker history <image>:latest
```

Check that each `wget` / `snapshot_download` / `COPY` layer shows the expected file size:

| Expected Layer | Approximate Size |
|----------------|-----------------|
| Diffusion model download | Matches HuggingFace file size (e.g. ~28GB for Wan 14B) |
| VAE download | ~200-500MB |
| Text encoder download | ~5-12GB depending on model |
| snapshot_download (multi-file) | Sum of all repo files |

If a download layer shows 0B or a suspiciously small size, the download failed silently (e.g. got an HTML error page instead of the weights).

For containers small enough to start quickly, you can also verify directly:

```bash
docker run --rm <image>:latest ls -lh /opt/comfyui/models/<path>/
```

Or check file integrity with a quick size sanity check:

```bash
docker run --rm <image>:latest find /opt/comfyui/models -name "*.safetensors" -exec ls -lh {} \;
```

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
| `gui/comfyui/Dockerfile.trellis2` | Standalone Dockerfile for TRELLIS-2 (CUDA 12.6 + torch 2.7.0) |
| `gui/comfyui/Dockerfile.wanvideo` | Dockerfile for WanVideo (layers on comfyui-sdxl base) |

## Build Issues Encountered

### WanVideo — Clean Build
WanVideo layers on `comfyui-sdxl:latest` (torch 2.6.0 + cu124). All models use standard `folder_paths` and download via `wget`. No issues.

### TRELLIS-2 — Required Standalone Image

The TRELLIS-2 container could not layer on the existing `comfyui-sdxl:latest` base due to dependency conflicts:

1. **Torch version mismatch**: The Trellis2 pre-built wheels (cumesh, nvdiffrast, flex_gemm, o_voxel) require torch 2.7.0. The base image ships torch 2.6.0+cu124, and torch 2.7.0 is not available for cu124 — only cu126.

2. **CUDA toolkit mismatch**: Attempting to install torch 2.7.0+cu126 on the cu124 base caused `undefined symbol: cudaGetDriverEntryPointByVersion` errors because the CUDA 12.4 toolkit lacks symbols torch 2.7.0+cu126 expects.

3. **xformers version pinning**: Unpinned `pip install xformers` pulled torch 2.10.0, breaking all torch 2.7.0 wheel compatibility. Fixed by pinning `xformers==0.0.30`.

4. **o_voxel vs cumesh circular dependency**: The o_voxel wheel declares cumesh as a git dependency (`git+https://github.com/JeffreyXiang/CuMesh.git`), which conflicts with the local cumesh wheel. Fixed with `pip install --no-deps`.

5. **DINOv3 gated repo**: `facebook/dinov3-vitl16-pretrain-lvd1689m` is a gated HuggingFace repo requiring authentication. Added `HF_TOKEN` build arg. Additionally, Facebook requires **manual review** of access requests — this is not instant and can take hours or days. No ungated alternative exists; DINOv3 is architecturally required by TRELLIS-2 as its image feature extractor. A SourceForge mirror exists at https://sourceforge.net/projects/dinov3.mirror/ as a fallback.

**Resolution**: Created a standalone Dockerfile using `nvidia/cuda:12.6.3-devel-rockylinux9` as the base, installing torch 2.7.0+cu126 from scratch. This avoids all CUDA/torch version conflicts.

### Lesson for the Skill

When containerizing ComfyUI nodes with native CUDA extensions (wheels compiled against specific torch versions):
- Check the wheel filenames for torch version requirements (e.g., `wheels/Linux/Torch270/`)
- Match the CUDA base image to the torch index URL (cu124 → CUDA 12.4, cu126 → CUDA 12.6)
- Pin xformers to a version compatible with your torch version
- Use `--no-deps` for wheels with circular or git-based dependencies
- Check if any HuggingFace repos are gated before assuming `snapshot_download` will work without auth

## Runtime Debugging & Triage

### Host Setup: NVIDIA Driver 580.x BPF Device Filter Bug

When running containers with `--gpus all` on NVIDIA driver 580.x and kernel 6.1.x (Amazon Linux 2023), Docker fails immediately at container creation:

```
$ docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

docker: Error response from daemon: failed to create task for container: failed to create shim task:
OCI runtime create failed: runc create failed: unable to start container process: error during
container init: error running prestart hook #0: exit status 1, stdout: , stderr: Auto-detected mode
as 'legacy'
nvidia-container-cli: mount error: failed to add device rules: unable to generate new device filter
program from existing programs: unable to create new device filters program: load program: invalid
argument: last insn is not an exit or jmp
processed 0 insns (limit 1000000) max_states_per_insn 0 total_states 0 peak_states 0 mark_read 0:
unknown.
```

**What's happening**: The `--gpus all` flag triggers the nvidia-container-cli legacy code path, which attempts to load a BPF (Berkeley Packet Filter) program to set up device cgroup rules. The kernel's BPF verifier (in kernel 6.1.x) rejects the program because the generated bytecode doesn't end with a valid exit/jump instruction. This is a compatibility gap between the nvidia-container-toolkit's BPF program generator and the stricter BPF verifier in newer kernels.

**Environment where this was observed**:
- NVIDIA Driver: 580.126.09
- CUDA Version: 13.0
- Kernel: 6.1.161-183.298.amzn2023.x86_64
- OS: Amazon Linux 2023
- nvidia-container-toolkit: 1.18.1-1 and 1.18.2-1 (both affected)
- Docker: 25.0.14
- runc: 1.3.4

**What does NOT fix it**:
- Upgrading nvidia-container-toolkit from 1.18.1 to 1.18.2
- Generating a CDI spec alone (CDI is a separate device injection mechanism)
- Restarting Docker

**Solution**: Bypass the legacy BPF path entirely by using `--runtime=nvidia` with environment variables instead of `--gpus all`:

```bash
# Broken — triggers legacy BPF device filter
docker run --gpus all ...

# Working — uses nvidia container runtime directly, skips BPF
docker run --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  ...
```

The `--runtime=nvidia` flag tells Docker to use the nvidia-container-runtime for the entire container lifecycle, and the environment variables (`NVIDIA_VISIBLE_DEVICES`, `NVIDIA_DRIVER_CAPABILITIES`) tell the runtime which GPUs and capabilities to expose. This path does not use the BPF device filter.

**Prerequisites** (must be done once on the host):

```bash
# 1. Configure Docker to know about the nvidia runtime
sudo nvidia-ctk runtime configure --runtime=docker
# This adds to /etc/docker/daemon.json:
# { "runtimes": { "nvidia": { "args": [], "path": "nvidia-container-runtime" } } }

# 2. Generate CDI spec (good practice, enables CDI device injection as fallback)
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# 3. Restart Docker to pick up the runtime config
sudo systemctl restart docker
```

**Verification**:
```bash
$ docker run --rm --runtime=nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

# Should show the GPU table with no errors
```

**Impact on job templates**: Any job template or script using `--gpus all` must be updated to use the `--runtime=nvidia` pattern. See `gui/comfyui/job/template.yaml` for the working example.

Full host setup documented in `gui/design/host_config.md` and scripted in `gui/design/setup_gpu_docker.sh`.

### Container Startup: Slow `docker run` on Large Images

For images >50GB (e.g. comfyui-wanvideo at 140GB total), `docker run -d` can take 10-20+ minutes before the container appears in `docker ps`. Docker is preparing the overlay filesystem — not stuck.

**How to tell it's still working** (not hung):
```bash
# Disk usage should be growing
df -h /

# docker run process should still be alive
ps aux | grep "docker run"

# I/O activity on the volume
iostat -x 1 1
```

**Root cause**: Default gp3 EBS volumes ship with 125 MB/s throughput and 3000 IOPS. Unpacking 140GB of image layers at 125 MB/s takes ~18 minutes just for sequential I/O.

**Mitigation options** (can be applied live without reboot):

| Option | Change | Cost Impact |
|--------|--------|-------------|
| Increase gp3 throughput | 125 → 1000 MB/s | +$35/month |
| Increase gp3 IOPS | 3000 → 9000+ | +$30/month (for 9000) |
| Use instance store NVMe | Mount nvme1n1 as Docker root | Free (if available on instance type) |

To modify EBS live: EC2 Console → Volumes → Modify Volume → change throughput/IOPS. Takes a few minutes to apply, no reboot needed.

**Instance store alternative**: Some instance types (g6e, p4d) include local NVMe SSDs that appear as unused disks (e.g. `nvme1n1`). These are much faster than EBS for Docker layer operations:

```bash
# Check for unused NVMe
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# Format and mount as Docker storage
sudo mkfs.xfs /dev/nvme1n1
sudo mkdir -p /mnt/docker
sudo mount /dev/nvme1n1 /mnt/docker
# Then configure Docker: "data-root": "/mnt/docker" in /etc/docker/daemon.json
```

Note: Instance store is ephemeral — data is lost on stop/terminate.

### Container Startup: Verifying ComfyUI Is Ready

Once the container appears in `docker ps`, check logs for successful startup:

```bash
docker logs <container-name> 2>&1 | tail -30
```

**Healthy startup indicators**:
- `ComfyUI version: X.Y.Z` — core loaded
- `Import times for custom nodes:` — nodes loaded
- `Assets scan(roots=['models']) completed` — models discovered
- `To see the GUI go to: http://0.0.0.0:8188` — server ready

**Common warnings that are safe to ignore**:
- `Could not load sageattention` — optional acceleration, not required
- `FantasyPortrait nodes not available: No module named 'onnx'` — unrelated optional feature
- `User settings have been changed to be stored on the server` — first-run migration

**Failure indicators**:
- `ModuleNotFoundError` for core dependencies — pip install failed during build
- `FileNotFoundError` for model paths — weights not baked to correct location
- Container exits immediately — check `docker logs` and `docker inspect --format='{{.State.ExitCode}}'`

### Ghost Container References

If `docker run` fails with "container name already in use" but `docker ps -a` shows nothing:

```bash
# Docker's internal state is stale — restart the daemon
sudo systemctl restart docker

# Then retry
docker run -d --name comfyui-session ...
```

This can happen when a previous `docker run` was interrupted (e.g. timeout, Ctrl+C) before Docker finished creating the container.
