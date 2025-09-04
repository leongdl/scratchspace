# Working Houdini RenderMan Commands

## Successfully Working hrender Commands

### Basic Render Command
```bash
./run-houdini-rdman.sh "hrender -v -d renderman1 /workspace/RMAN_test_02.hip"
```

### Specific Frame Render
```bash
./run-houdini-rdman.sh "hrender -v -F 5 -d renderman1 /workspace/RMAN_test_02.hip"
./run-houdini-rdman.sh "hrender -v -F 6 -d renderman1 /workspace/RMAN_test_02.hip"
```

### Chained Commands with Output Discovery
```bash
./run-houdini-rdman.sh "hrender -v -F 5 -d renderman1 /workspace/RMAN_test_02.hip" && find . -name "*.exr" -newer output/20250904_003628.exr
./run-houdini-rdman.sh "hrender -v -F 6 -d renderman1 /workspace/RMAN_test_02.hip" && ls -la render/RMAN_test_02.renderman1.0006.exr
```

## Key Fixes and Solutions

### 1. Segmentation Fault Resolution
- **Problem**: hrender was experiencing segmentation faults with various parameter combinations
- **Solution**: Use absolute paths and avoid certain parameter combinations like `-o` with custom output paths
- **Working Pattern**: Use `-d renderman1` to specify the driver and let it use default output paths

### 2. File Path Requirements
- **Problem**: Relative paths caused "Cannot find file" errors
- **Solution**: Always use absolute paths: `/workspace/RMAN_test_02.hip` instead of `RMAN_test_02.hip`

### 3. Output Parameter Issues
- **Problem**: Using `-o` flag caused AttributeError: 'NoneType' object has no attribute 'set'
- **Solution**: Let hrender use default output paths in the `render/` directory, then copy files as needed

### 4. Missing Node Type Warnings
- **Issue**: Warnings about missing Driver/deadline_cloud and Driver/deadline nodes
- **Status**: These are non-critical warnings for AWS Deadline Cloud integration - renders work fine despite these warnings

## Output File Patterns

### Default Output Location
- Files are saved to: `render/RMAN_test_02.renderman1.XXXX.exr`
- Where XXXX is the 4-digit frame number (e.g., 0005, 0006, 0011)

### File Sizes
- Typical output: ~1.28MB EXR files
- Format: OpenEXR with RGBA channels

## Environment Status
- Container: houdini-rdman-rhel
- Houdini Version: 20.0.896
- RenderMan: ProServer-26.3 with RenderMan for Houdini-26.3
- All license environments properly configured
- DSO loading working correctly

## Verified Working Frames
- Frame 5: Successfully rendered (1.28MB)
- Frame 6: Successfully rendered (1.28MB) 
- Frame 11: Successfully rendered (default frame)

## Command Structure
```bash
./run-houdini-rdman.sh "hrender [options] -d driver_name /workspace/file.hip"
```

### Key Parameters
- `-v`: Verbose output
- `-F N`: Render specific frame N
- `-d renderman1`: Use the renderman1 driver node
- `-e -f start end`: Render frame range (not tested yet)