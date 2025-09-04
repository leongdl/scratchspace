# Houdini RenderMan DSO and Library Issues

## Overview

This document summarizes the Dynamic Shared Object (DSO) and library dependency issues encountered when running Houdini with RenderMan in a containerized environment, along with their root causes, impacts, and solutions.

## Root Cause: Missing X11/XCB Libraries

The core issue stems from missing X11 and XCB libraries in the UBI 9.3 base container:

### Missing Libraries:
- `libxkbcommon.so.0`
- `libxkbcommon-x11.so.0`
- `libxcb-icccm.so.4`
- `libxcb-image.so.0`
- `libxcb-keysyms.so.1`
- `libxcb-render-util.so.0`

### Why These Are Missing:
- UBI (Universal Base Image) is a minimal RHEL-based container
- X11/XCB libraries are not included by default in headless environments
- These packages are not available in UBI repositories without additional subscriptions

## Impact Analysis

### 1. RenderMan License System
**Error**: `ROP: unknown error: 2`
**Cause**: RenderMan's `LicenseApp` requires X11 libraries to initialize
**Impact**: Complete failure of RenderMan ROP rendering

### 2. Houdini UI Libraries
**Error**: `libHoudiniUI.so` cannot load
**Cause**: Depends on `libxkbcommon.so.0`
**Impact**: UI-related DSOs fail to load

### 3. RenderMan UI Components
**Failing Libraries**:
- `rfh_ipr.so` - Interactive Progressive Rendering
- `rfh_prefs.so` - Preferences UI

**Error**: `undefined symbol: _ZN17UI_OHEventHandler23ohRequestDeferredUpdateEv`
**Cause**: UI symbols are only available when `libHoudiniUI.so` loads successfully
**Impact**: RenderMan interactive features unavailable

### 4. Other Houdini DSOs
**Example**: `/opt/houdini/packages/kinefx/dso/kinefx.so`
**Error**: `libxkbcommon.so.0: cannot open shared object file`
**Impact**: Some Houdini features may be unavailable

## Library Loading Test Results

### ✅ Successfully Loading (11/13 RenderMan libraries):
- `d_rfh.so` - RenderMan display driver
- `dynamicarray.so` - Dynamic array support
- `init.so` - Initialization library
- `materialbuilder.so` - Material builder
- `pxrosl.so` - Pixar OSL support
- `rfh_prefs_init.so` - Preferences initialization
- `uniformarray.so` - Uniform array support
- `libpxrcore.so` - Core Pixar library
- `libstats.so` - Statistics library
- `rfh_batch.so` - Batch rendering support
- `impl_openvdb.so` - OpenVDB implementation

### ❌ Failed to Load (2/13 RenderMan libraries):
- `rfh_ipr.so` - Interactive rendering (UI dependency)
- `rfh_prefs.so` - Preferences UI (UI dependency)

## Solutions Implemented

### 1. HOUDINI_DSO_ERROR Environment Variable
**Setting**: `HOUDINI_DSO_ERROR=2`
**Effect**: 
- Silently ignores DSO loading errors
- Prevents crashes from missing dependencies
- Allows core functionality to continue working

**Implementation**:
- Added to Dockerfile: `/opt/houdini/houdini/config/houdini.env`
- Added to run script: `export HOUDINI_DSO_ERROR=2`

### 2. Graceful Degradation
**Result**: 
- Core RenderMan libraries load successfully (85% success rate)
- Batch rendering components work
- Only UI-related features are affected

## Current Status

### ✅ Working:
- Houdini starts and loads scenes
- RenderMan core libraries load
- Scene analysis and node detection
- Direct `prman` rendering works perfectly

### ❌ Still Failing:
- RenderMan ROP rendering (`ROP: unknown error: 2`)
- Interactive RenderMan features
- Some Houdini UI-dependent features

## Alternative Solutions

### Option 1: Install Missing Libraries (Challenging)
- Requires CentOS Stream/Rocky Linux base image
- Or manual RPM installation from external sources
- Increases container size and complexity

### Option 2: Direct prman Rendering (Recommended)
- Bypass Houdini ROP entirely
- Export geometry/materials separately
- Use `prman` command directly
- Proven to work in current setup

### Option 3: Headless RenderMan License Server
- Use network-based license server
- May reduce X11 dependency requirements
- Requires license server infrastructure

## Dependency Chain Analysis

```
RenderMan ROP
    ↓ depends on
RenderMan License System (LicenseApp)
    ↓ depends on
X11/XCB Libraries (libxkbcommon.so.0, etc.)
    ↓
❌ MISSING in UBI container

RenderMan UI Libraries (rfh_ipr.so, rfh_prefs.so)
    ↓ depends on
UI_OHEventHandler symbols
    ↓ defined in
libHoudiniUI.so
    ↓ depends on
X11/XCB Libraries
    ↓
❌ MISSING in UBI container
```

## Recommendations

1. **Use `HOUDINI_DSO_ERROR=2`** for stability in headless environments
2. **Focus on direct prman rendering** for production workflows
3. **Consider alternative base images** if full UI support is required
4. **Monitor RenderMan updates** for potential headless improvements
5. **Document workarounds** for specific missing features

## Testing Commands

```bash
# Test library loading
./run-houdini-rdman.sh "hython /workspace/test_so_loading.py"

# Test DSO error handling
./run-houdini-rdman.sh "echo 'HOUDINI_DSO_ERROR:' \$HOUDINI_DSO_ERROR"

# Test RenderMan integration
./run-houdini-rdman.sh "hython /workspace/render_ris_cpu.py /render/RMAN_test_02.hip /workspace/output"

# Test direct prman (works)
./run-houdini-rdman.sh "prman -version"
```

## Conclusion

The DSO issues are well-understood and manageable. While full ROP rendering remains blocked by license system dependencies, the core RenderMan functionality is available through direct `prman` usage. The `HOUDINI_DSO_ERROR=2` setting provides a stable foundation for headless Houdini operations with graceful degradation of UI-dependent features.