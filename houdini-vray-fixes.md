# Houdini VRay Integration Fixes

This document contains all the fixes and solutions implemented for VRay integration with Houdini in Docker containers.

## Issue 1: libHoudiniUI.so DSO Loading Error

**Error:**
```
Houdini DSO error on '/usr/redshift/redshift4houdini/20.5.613/dso/redshift4houdini.so'
libHoudiniUI.so: cannot open shared object file: No such file or directory
```

**Root Cause:** VRay plugins couldn't find Houdini's DSO libraries.

**Solution:** Add Houdini DSO library path to `LD_LIBRARY_PATH` in all launcher scripts:

```bash
export LD_LIBRARY_PATH="/opt/houdini/dsolib:$LD_LIBRARY_PATH"
```

**Applied to:**
- `/usr/local/bin/vray` (VRay standalone launcher)
- `/usr/local/bin/houdini-vray` (Houdini-VRay integration launcher)
- `/usr/local/bin/houdini-vray-redshift` (Combined launcher)

## Issue 2: ModuleNotFoundError: No module named 'soho'

**Error:**
```
File "/opt/vray/vfh_home/soho/python3.11/vfh_ipr.py", line 20, in main
    import soho
ModuleNotFoundError: No module named 'soho'
```

**Root Cause:** VRay's PYTHONPATH didn't include Houdini's Python modules.

**Solution:** Update PYTHONPATH in VRay package configuration and launcher scripts:

### Dockerfile.houdini-vray - VRay Package Configuration:
```dockerfile
# Create Houdini package configuration for V-Ray
RUN echo '{\
    "env": [\
        { "INSTALL_ROOT" : "/opt/vray" },\
        { "VRAY_APPSDK"     : "${INSTALL_ROOT}/appsdk" },\
        { "VRAY_OSL_PATH"   : "${INSTALL_ROOT}/appsdk/bin" },\
        { "VRAY_UI_DS_PATH" : "${INSTALL_ROOT}/ui" },\
        { "VFH_HOME"        : "${INSTALL_ROOT}/vfh_home" },\
        { "PYTHONPATH" : [\
            "${INSTALL_ROOT}/appsdk/python",\
            "${HFS}/python/lib/python3.11/site-packages",\
            "${HFS}/python/lib/python3.11/site-packages-forced"\
        ] },\
        { "PATH" : [\
            "${VRAY_APPSDK}/bin",\
            "${VFH_HOME}/bin"\
        ] },\
        { "HOUDINI13_VOLUME_COMPATIBILITY" : 1 },\
        { "HDF5_DISABLE_VERSION_CHECK"     : 1 }\
    ],\
    "path" : [\
        "${VFH_HOME}"\
    ]\
}' > /opt/houdini/packages/vray_for_houdini.json
```

### Launcher Scripts PYTHONPATH:
```bash
export PYTHONPATH=$VRAY_APPSDK/python:/opt/houdini/python/lib/python3.11/site-packages:/opt/houdini/python/lib/python3.11/site-packages-forced:$PYTHONPATH
```

## Issue 3: Invalid VRay Node Type Name

**Error:**
```
hou.OperationFailed: The attempted operation failed.
Invalid node type name
```

**Root Cause:** Using incorrect node type name `"vray_renderer"` instead of `"vray"`.

**Solution:** Use correct VRay node type from nodes.md analysis:

```python
# Correct VRay node creation
vray = hou.node("/out").createNode("vray", "vray_renderer")
```

**Available node types confirmed:**
- `vray` ✅ (correct)
- `Redshift_ROP` (for Redshift)
- `karma` (for Karma)

## Issue 4: VRay Parameter Names

**Error:**
```
AttributeError: 'NoneType' object has no attribute 'set'
```

**Root Cause:** Using incorrect parameter names for VRay renderer.

**Solution:** Use correct VRay parameter names from nodes.md analysis:

### VRay Parameters (first 20):
1. `execute`
2. `renderpreview`
3. `executebackground`
4. `renderdialog`
5. `trange` ✅
6. `f1` ✅
7. `f2` ✅
8. `f3` ✅
9. `take`
10. `VRayRendererFolderExport_5`
11. `soho_pipecmd`
12. `soho_program`
13. `soho_shopstyle`
14. `soho_ipr_support`
15. `soho_previewsupport`
16. `soho_outputmode`
17. `soho_diskfile` ✅ (output file)
18. `soho_compression`
19. `soho_foreground`
20. `soho_initsim`

### Correct Parameter Usage:
```python
# Output file
if vray.parm("soho_diskfile"):
    vray.parm("soho_diskfile").set("/work/vray_output.png")

# Frame range (these exist and work)
if vray.parm("trange"):
    vray.parm("trange").set(1)
if vray.parm("f1"):
    vray.parm("f1").set(1)
if vray.parm("f2"):
    vray.parm("f2").set(1)
if vray.parm("f3"):
    vray.parm("f3").set(1)
```

## Issue 5: ModuleNotFoundError: No module named '_vfh_ipr'

**Error:**
```
File "/opt/vray/vfh_home/soho/python3.11/vfh_ipr.py", line 22, in main
    import _vfh_ipr
ModuleNotFoundError: No module named '_vfh_ipr'
```

**Root Cause:** When using `hrender` directly, VRay environment variables weren't set.

**Solution:** Include full VRay environment setup in template.yaml:

```bash
bash -c "cd /opt/houdini && source ./houdini_setup_bash && \
export LD_LIBRARY_PATH=\"/opt/houdini/dsolib:\$LD_LIBRARY_PATH\" && \
export VRAY_PATH=/opt/vray && \
export VRAY_APPSDK=\$VRAY_PATH/appsdk && \
export VFH_HOME=\$VRAY_PATH/vfh_home && \
export VRAY_OSL_PATH=\$VRAY_APPSDK/bin && \
export VRAY_UI_DS_PATH=\$VRAY_PATH/ui && \
export PYTHONPATH=\$VRAY_APPSDK/python:/opt/houdini/python/lib/python3.11/site-packages:/opt/houdini/python/lib/python3.11/site-packages-forced:\$PYTHONPATH && \
export PATH=\$VRAY_APPSDK/bin:\$VFH_HOME/bin:\$PATH && \
export HOUDINI_PATH=\$VFH_HOME:\$HOUDINI_PATH && \
export HOUDINI13_VOLUME_COMPATIBILITY=1 && \
export HDF5_DISABLE_VERSION_CHECK=1 && \
/opt/houdini/bin/hrender -e -d /out/vray_renderer -f 1 1 /work/simple_scene_vray.hip -v"
```

## Issue 6: Inconsistent VRay Launcher Scripts

**Problem:** VRay standalone launcher (`/usr/local/bin/vray`) had different environment setup than houdini-vray launcher.

**Solution:** Ensure both launchers have identical VRay environment setup:

### Required VRay Environment Variables:
```bash
export VRAY_PATH=/opt/vray
export VRAY_APPSDK=$VRAY_PATH/appsdk
export VFH_HOME=$VRAY_PATH/vfh_home
export VRAY_OSL_PATH=$VRAY_APPSDK/bin
export VRAY_UI_DS_PATH=$VRAY_PATH/ui
export PYTHONPATH=$VRAY_APPSDK/python:/opt/houdini/python/lib/python3.11/site-packages:/opt/houdini/python/lib/python3.11/site-packages-forced:$PYTHONPATH
export PATH=$VRAY_APPSDK/bin:$VFH_HOME/bin:$PATH
export HOUDINI_PATH=$VFH_HOME:$HOUDINI_PATH
export HOUDINI13_VOLUME_COMPATIBILITY=1
export HDF5_DISABLE_VERSION_CHECK=1
```

## Final Working Configuration

### houdini-vray.py (Simplified):
```python
import hou
import os

# Create a new Houdini scene
hou.hipFile.clear()

# Create geometry and camera (same as working houdini.py)
geo = hou.node("/obj").createNode("geo", "simple_geo")
box = geo.createNode("box", "simple_box")
color = geo.createNode("color", "red_color")
color.setInput(0, box)
color.parm("colorr").set(1.0)
color.parm("colorg").set(0.0)
color.parm("colorb").set(0.0)

cam = hou.node("/obj").createNode("cam", "render_cam")
cam.parmTuple("t").set((5, 5, 5))
cam.parmTuple("r").set((-30, 45, 0))

# Create VRay renderer with correct node type
vray = hou.node("/out").createNode("vray", "vray_renderer")

# Set parameters with correct names
if vray.parm("soho_diskfile"):
    vray.parm("soho_diskfile").set("/work/vray_output.png")

if vray.parm("trange"):
    vray.parm("trange").set(1)
if vray.parm("f1"):
    vray.parm("f1").set(1)
if vray.parm("f2"):
    vray.parm("f2").set(1)
if vray.parm("f3"):
    vray.parm("f3").set(1)

# Save scene
hou.hipFile.save("/work/simple_scene_vray.hip")
```

### template.yaml (VRay rendering):
```yaml
# Use hrender directly with full VRay environment
docker run --rm \
  --network host \
  --ulimit stack=52428800 \
  -v "$(pwd)/houdini_vray_render:/work" \
  -w /work \
  -e SESI_LMHOST \
  -e VRAY_AUTH_CLIENT_FILE_PATH \
  -e VRAY_AUTH_CLIENT_SETTINGS \
  {{Param.ECR_REGISTRY}}/{{Param.HOUDINI_REPOSITORY}}:{{Param.HOUDINI_TAG}} \
  bash -c "cd /opt/houdini && source ./houdini_setup_bash && [VRay environment setup] && /opt/houdini/bin/hrender -e -d /out/vray_renderer -f 1 1 /work/simple_scene_vray.hip -v"
```

## Key Principles

1. **No Fallbacks:** Focus on VRay-specific solutions, don't fall back to other renderers
2. **Consistent Environment:** Ensure all launcher scripts have identical VRay setup
3. **Correct Parameter Names:** Use actual VRay parameter names from nodes.md analysis
4. **Complete Environment Setup:** Include all VRay environment variables when using hrender directly
5. **DSO Library Path:** Always include `/opt/houdini/dsolib` in `LD_LIBRARY_PATH`

## Verification Steps

1. Check available node types: VRay should show `['vray']`
2. Check VRay parameters: Should include `soho_diskfile`, `trange`, `f1`, `f2`, `f3`
3. Test VRay node creation: `hou.node("/out").createNode("vray", "vray_renderer")`
4. Test parameter setting: `vray.parm("soho_diskfile").set("/work/output.png")`
5. Test rendering: `hrender -e -d /out/vray_renderer -f 1 1 scene.hip`

## Container Build

After making changes to Dockerfile.houdini-vray:
```bash
./build_and_push_houdini.sh
```

Image: `224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:houdini-latest`