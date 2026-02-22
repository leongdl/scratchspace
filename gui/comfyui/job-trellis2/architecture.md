# TRELLIS-2 Container Build Architecture

## The GLIBCXX Problem

The ComfyUI-Trellis2 node ships pre-built `.whl` files for its CUDA extensions (cumesh, flex_gemm, o_voxel, nvdiffrast). These wheels were compiled on a system with GCC 13+ which provides `GLIBCXX_3.4.32`. Rocky Linux 9 (our base image `nvidia/cuda:12.6.3-devel-rockylinux9`) ships GCC 11 with `libstdc++.so.6.0.29`, which only goes up to `GLIBCXX_3.4.29`.

When the pre-built wheels are installed as-is, the native `.so` extensions fail at import time:

```
ImportError: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.32' not found
  (required by cumesh/_C.cpython-312-x86_64-linux-gnu.so)
```

This affects 3 of the 4 wheels:
- `cumesh` — 4 native `.so` files (`_C`, `_cubvh`, `_cumesh_xatlas`, `_xatlas`)
- `flex_gemm` — 1 native `.so` file (`kernels/cuda`)
- `o_voxel` — 1 native `.so` file (`_C`)
- `nvdiffrast` — unaffected (JIT compiles at runtime)

## The tiled_flexible_dual_grid_to_mesh Problem

The upstream Microsoft TRELLIS.2 repo's `o-voxel` package does NOT include `tiled_flexible_dual_grid_to_mesh`. This function was added by the ComfyUI-Trellis2 author (visualbruno) in their custom wheel. The ComfyUI-Trellis2 node code imports it:

```python
# trellis2/models/sc_vaes/fdg_vae.py
from o_voxel.convert import flexible_dual_grid_to_mesh, tiled_flexible_dual_grid_to_mesh
```

Building o_voxel purely from the upstream source results in:
```
ImportError: cannot import name 'tiled_flexible_dual_grid_to_mesh' from 'o_voxel.convert'
```

## The Solution: Hybrid Install (Wheel Python + Source-Built .so)

The approach that works:

1. Install the pre-built wheels with `--no-deps` (gets the correct Python code including `tiled_flexible_dual_grid_to_mesh`)
2. Build the native CUDA extensions from source on Rocky 9 (links against the system's libstdc++)
3. Swap the wheel's `.so` files with the source-built ones
4. Patch one import name mismatch (`_xatlas` vs `_cumesh_xatlas`)

### Why This Works

The pre-built wheels contain two things:
- Python source files (`.py`) — these have the correct API including tiled functions
- Native extensions (`.so`) — these are the ones that need GLIBCXX_3.4.32

By keeping the Python files from the wheels but replacing the `.so` files with locally-compiled versions, we get both correct API compatibility AND correct ABI compatibility.

### The _xatlas Naming Mismatch

The upstream CuMesh source builds the xatlas extension as `_cumesh_xatlas` (module init function `PyInit__cumesh_xatlas`), but the wheel's Python code imports it as `_xatlas`. Simply renaming the `.so` file doesn't work because the Python module init function name is baked into the binary.

Fix: patch `cumesh/xatlas.py` to import the source-built name:
```python
# Before (wheel version):
from . import _xatlas
# After (patched):
from . import _cumesh_xatlas as _xatlas
```

## Source Repositories for CUDA Extensions

| Package | Source | What It Does |
|---------|--------|-------------|
| CuMesh | [JeffreyXiang/CuMesh](https://github.com/JeffreyXiang/CuMesh) | CUDA mesh utilities — remeshing, decimation, UV unwrapping |
| FlexGEMM | [JeffreyXiang/FlexGEMM](https://github.com/JeffreyXiang/FlexGEMM) | Triton-based sparse convolution for voxel structures |
| o-voxel | [microsoft/TRELLIS.2](https://github.com/microsoft/TRELLIS.2) (subdir `o-voxel/`) | O-Voxel representation — mesh↔voxel conversion |
| nvdiffrast | [NVlabs/nvdiffrast](https://github.com/NVlabs/nvdiffrast) (tag v0.4.0) | Differentiable rasterization (JIT compiled, no GLIBCXX issue) |

All source builds require:
- `CUDA_HOME=/usr/local/cuda` (provided by the devel base image)
- `ninja` and `wheel` pip packages
- `--no-build-isolation` flag (so builds can see the installed torch)

## Dockerfile Build Strategy

```dockerfile
# Step 1: Build native .so files from source, save them to /tmp
RUN git clone --recursive https://github.com/JeffreyXiang/CuMesh.git /tmp/ext/CuMesh && \
    CUDA_HOME=/usr/local/cuda pip install --user /tmp/ext/CuMesh --no-build-isolation
# (save .so files to /tmp/built-sos/, repeat for FlexGEMM and o-voxel)

# Step 2: Install pre-built wheels (correct Python code)
RUN pip install --user --no-deps \
    .../wheels/Linux/Torch270/cumesh-0.0.1-cp312-cp312-linux_x86_64.whl \
    .../wheels/Linux/Torch270/flex_gemm-0.0.1-cp312-cp312-linux_x86_64.whl \
    .../wheels/Linux/Torch270/o_voxel-0.0.1-cp312-cp312-linux_x86_64.whl \
    .../wheels/Linux/Torch270/nvdiffrast-0.4.0-cp312-cp312-linux_x86_64.whl

# Step 3: Swap .so files
RUN cp /tmp/built-sos/cumesh/* site-packages/cumesh/ && \
    cp /tmp/built-sos/flex_gemm/* site-packages/flex_gemm/kernels/ && \
    cp /tmp/built-sos/o_voxel/* site-packages/o_voxel/

# Step 4: Patch xatlas import
RUN sed -i 's/from \. import _xatlas/from . import _cumesh_xatlas as _xatlas/' \
    site-packages/cumesh/xatlas.py
```

## Version Matrix (Verified Working)

| Component | Version | Constraint |
|-----------|---------|-----------|
| Base image | `nvidia/cuda:12.6.3-devel-rockylinux9` | CUDA 12.6 required for torch cu126 |
| Python | 3.12 | Wheels are cp312 |
| PyTorch | 2.7.0+cu126 | Wheels require torch 2.7.0; cu126 needs CUDA 12.6 |
| xformers | 0.0.30 | Pinned to match torch 2.7.0 |
| GCC (system) | 11.5.0 | Rocky 9 default, provides GLIBCXX up to 3.4.29 |
| cumesh | 0.0.1 (wheel Python + source .so) | Wheel from ComfyUI-Trellis2 |
| flex_gemm | 0.0.1 (wheel Python + source .so) | Wheel from ComfyUI-Trellis2 |
| o_voxel | 0.0.1 (wheel Python + source .so) | Wheel from ComfyUI-Trellis2 |
| nvdiffrast | 0.4.0 (wheel, JIT) | No native .so issue |

## What Does NOT Work

| Approach | Failure |
|----------|---------|
| Pre-built wheels as-is | `GLIBCXX_3.4.32 not found` — Rocky 9 only has 3.4.29 |
| Pure source build (all from upstream) | `tiled_flexible_dual_grid_to_mesh` missing from o_voxel |
| Installing gcc-toolset-13/14 | Only provides static libs and linker scripts, not the shared runtime |
| Renaming `_cumesh_xatlas.so` → `_xatlas.so` | `PyInit__xatlas` not found — init function name is baked in |
| Layering on `comfyui-sdxl:latest` (torch 2.6.0+cu124) | `undefined symbol: cudaGetDriverEntryPointByVersion` |

## Runtime Requirements

```bash
docker run -d \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --network host \
  --name comfyui-trellis2 \
  comfyui-trellis2:latest
```

Note: `--gpus all` may fail on some hosts with `unable to create new device filters program`. Use `--runtime=nvidia` with explicit env vars instead.
