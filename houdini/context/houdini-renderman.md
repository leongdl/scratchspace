# RenderMan for Houdini 26.1 Documentation

## Overview

RenderMan for Houdini (RFH) is Pixar's rendering plugin that integrates RenderMan rendering capabilities directly into SideFX Houdini. This is not a standalone executable but rather a comprehensive plugin system that extends Houdini's rendering pipeline.

## Version Information

- **Version**: RenderMan for Houdini 26.1
- **Build**: linuxRHEL7_x86-64_gcc93icx232_external_release
- **Build Date**: Sun Apr 21 20:34:11 2024 @2324837
- **Supported Houdini Versions**: 19.0.720, 19.5.805, 20.0.653
- **Python Versions**: 2.7, 3.7, 3.9

## Installation Structure

The RenderMan for Houdini plugin is installed at `/opt/pixar/RenderManForHoudini-26.1/` with the following structure:

```
/opt/pixar/RenderManForHoudini-26.1/
├── 2.7/          # Python 2.7 support (legacy)
├── 3.7/          # Python 3.7 support
└── 3.9/          # Python 3.9 support
    ├── 19.0.720/ # Houdini 19.0.720 support
    ├── 19.5.805/ # Houdini 19.5.805 support
    └── 20.0.653/ # Houdini 20.0.653 support
        ├── config/           # UI configuration and icons
        ├── display/          # Display drivers
        ├── dso/             # Dynamic shared objects (plugins)
        ├── dsolib/          # USD and rendering libraries
        ├── help/            # Documentation
        ├── husdplugins/     # Houdini USD plugins
        ├── lib/             # Core libraries
        ├── otls/            # Operator Type Libraries (HDAs)
        ├── python3.9libs/   # Python libraries
        ├── python_panels/   # UI panels
        ├── scripts/         # VOP scripts
        ├── soho/            # SOHO rendering framework
        └── toolbar/         # Shelf tools
```

## Key Components

### 1. Rendering Framework
- **SOHO Integration**: Extends Houdini's Scene Operator for Houdini Output (SOHO) framework
- **RFH.py**: Main rendering command module that interfaces with RenderMan
- **Render Command**: `rman_start` command for initiating renders

### 2. Node Types (HDAs)
Located in `otls/` directory:
- **LOP.hda**: Lighting/Look Development nodes for USD workflows
- **OBJ.hda**: Object-level nodes (lights, cameras)
- **ROP.hda**: Render Output nodes
- **SHOP.hda**: Shader nodes (legacy)
- **VOP.hda**: VEX Operator nodes for shader building
- **TOP.hda**: Task Operator nodes for PDG workflows

### 3. Light Types
RenderMan provides various light types accessible through Houdini:
- **PxrRectLight**: Rectangular area light
- **PxrSphereLight**: Spherical point light
- **PxrDistantLight**: Directional/sun light
- **PxrDomeLight**: Environment/HDRI light
- **PxrDiskLight**: Disk-shaped area light
- **PxrCylinderLight**: Cylindrical area light
- **PxrMeshLight**: Geometry-based light
- **PxrPortalLight**: Portal light for interiors
- **PxrEnvDayLight**: Physical sky model
- **PxrVolumeLight**: Volumetric light

### 4. Light Filters
- **PxrBarnLightFilter**: Barn door effects
- **PxrCookieLightFilter**: Gobo/cookie patterns
- **PxrRampLightFilter**: Gradient falloffs
- **PxrRodLightFilter**: Rod-shaped occlusion
- **PxrIntMultLightFilter**: Intensity multiplier

### 5. Shading System
- **Lama**: Modern layered material system
- **PxrSurface**: Legacy surface shader
- **PxrOSL**: Open Shading Language support
- **Material Builder**: Node-based shader authoring

### 6. USD Integration
- **Hydra Delegate**: hdPrman for USD rendering
- **USD Plugins**: Schema and discovery plugins
- **Shader Translators**: USD material conversion

## Rendering Modes

### 1. Batch Rendering
Standard offline rendering mode for final quality output.

### 2. Interactive Preview Rendering (IPR)
Real-time preview rendering with live updates as scene changes.

### 3. Flipbook Rendering
Sequence rendering for animation playback.

### 4. RIB Generation
Export RenderMan Interface Bytestream files for external rendering.

## Command Line Interface

RenderMan for Houdini integrates with Houdini's `hrender` command:

```bash
# Render with RenderMan ROP node
hrender -d /out/renderman_rop1 scene.hip

# Render specific frame
hrender -f 1 -d /out/renderman_rop1 scene.hip

# Render frame range
hrender -e -f 1 10 -d /out/renderman_rop1 scene.hip
```

### RenderMan-Specific Parameters

The plugin adds RenderMan-specific parameters to Houdini's rendering system:

- **Integrator Settings**: Path tracing, direct lighting, subsurface
- **Sampling Controls**: Pixel samples, light samples, BXDF samples
- **Ray Depth**: Diffuse, specular, transmission bounces
- **Denoising**: AI-based noise reduction
- **XPU Rendering**: GPU-accelerated rendering (when available)

## Environment Variables

Key environment variables for RenderMan for Houdini:

- **RFHTREE**: Path to RenderMan for Houdini installation
- **RMANTREE**: Path to RenderMan installation (if separate)
- **HOUDINI_PATH**: Include RFH path for plugin discovery
- **PIXAR_LICENSE_FILE**: RenderMan license server

## Python API

### Core Modules
- **rfh**: Main RenderMan for Houdini Python module
- **rfh.config**: Configuration and licensing
- **rfh.log**: Logging utilities
- **rfh.prefs**: User preferences
- **RFH**: SOHO rendering interface
- **RFHhooks**: Rendering hooks and callbacks

### Example Usage
```python
import hou
import rfh

# Get RenderMan ROP node
rop = hou.node('/out/renderman1')

# Configure render settings
rop.parm('ri_integrator').set('PxrPathTracer')
rop.parm('ri_maxdiffusedepth').set(3)
rop.parm('ri_maxspeculardepth').set(5)

# Start render
rop.render()
```

## Features

### Advanced Rendering
- **Path Tracing**: Physically accurate global illumination
- **Subsurface Scattering**: Realistic skin and translucent materials
- **Volumetrics**: Clouds, smoke, and atmospheric effects
- **Motion Blur**: Camera and transformation blur
- **Depth of Field**: Realistic camera focus effects

### Production Tools
- **Denoising**: AI-powered noise reduction
- **AOVs**: Arbitrary Output Variables for compositing
- **Cryptomatte**: Automatic ID mattes
- **Statistics**: Detailed render statistics and profiling
- **Tractor Integration**: Render farm submission

### USD Workflow
- **Hydra Integration**: Native USD rendering
- **MaterialX Support**: Standard material exchange
- **Scene Graph**: Efficient scene representation
- **Instancing**: Memory-efficient geometry replication

## Licensing

RenderMan for Houdini requires:
1. Valid RenderMan license
2. Compatible Houdini license
3. Proper license server configuration

## Integration with Docker

When using RenderMan for Houdini in Docker containers:

1. **Environment Setup**: Ensure RFHTREE and related paths are configured
2. **License Access**: Configure license server access from container
3. **Plugin Loading**: Add RFH path to HOUDINI_PATH
4. **Dependencies**: Install required system libraries

### Docker Environment Variables
```dockerfile
ENV RFHTREE=/opt/pixar/RenderManForHoudini-26.1/3.9/20.0.653
ENV HOUDINI_PATH=$RFHTREE:$HOUDINI_PATH
ENV PIXAR_LICENSE_FILE=@license-server:1999
```

## Troubleshooting

### Common Issues
1. **License Errors**: Verify license server connectivity
2. **Plugin Not Loading**: Check HOUDINI_PATH configuration
3. **Missing Dependencies**: Install required system libraries
4. **Version Mismatch**: Ensure Houdini and RFH versions are compatible

### Debug Information
- Check Houdini console for RFH loading messages
- Verify plugin paths in Houdini's About dialog
- Use `rfh.config.cfg().warn_if_no_access()` to check licensing

## Performance Considerations

### Optimization Tips
1. **Sampling**: Balance quality vs. render time
2. **Ray Depths**: Limit bounces for faster renders
3. **Denoising**: Use AI denoising to reduce sample counts
4. **XPU**: Leverage GPU acceleration when available
5. **Instancing**: Use efficient geometry representation

This documentation provides a comprehensive overview of RenderMan for Houdini 26.1 capabilities, structure, and integration within the Houdini ecosystem.