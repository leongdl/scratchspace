# Houdini Docker Installation Guide

This document summarizes the process of installing Houdini and VRay for Houdini in a Docker container, including the steps for iterating on the installation and testing.

## Houdini Overview

Houdini is a 3D animation software application developed by SideFX. It's used for visual effects, game development, and other 3D content creation. The Docker container includes:

- Houdini 20.5.613 (command-line rendering capabilities)
- VRay for Houdini 7.00.10 (rendering plugin)

## Installation Process

### 1. Dependencies Installation
- Added specific dependencies for Houdini:
  - X11 libraries: `libSM`, `libICE`, `libXt`, `libXcomposite`, etc.
  - Audio libraries: `alsa-lib`
  - OpenGL libraries: `mesa-libGL`, `mesa-libGLU`, `libglvnd-glx`, `libglvnd-opengl`

### 2. Environment Setup
- Set up essential Houdini environment variables:
  - `HFS`: Houdini installation directory
  - `HB`: Houdini binary directory
  - `HDSO`: Houdini DSO library directory
  - `PATH`: Updated to include Houdini binaries
  - `HOUDINI_VERSION`: Version information

### 3. Houdini Installation
- Installed Houdini from the extracted tarball
- Used the `houdini.install` script with automated options:
  - `--auto-install`: Non-interactive installation
  - `--accept-EULA`: Accept the End User License Agreement
  - `--install-houdini`: Install the core Houdini software
  - `--install-license`: Install licensing components
  - `--install-dir /opt/houdini`: Set installation directory

### 4. VRay for Houdini Installation
- Installed VRay from the extracted installer
- Used the `vray_adv_70010_houdini20.5_gcc11_linux.run` script with options:
  - `--target /opt/vray`: Set installation directory
  - `--accept-eula`: Accept the End User License Agreement
  - `--auto-install`: Non-interactive installation

### 5. Launcher Scripts
- Created launcher scripts for both Houdini and VRay:
  - `houdini`: Sets up the environment and launches the Houdini renderer
  - `vray`: Sets up the environment and launches the VRay renderer

### 6. Verification
- Created verification scripts to check both installations
- Verified binaries exist and can be executed
- Tested command-line functionality with `--help` flags

## Houdini Directory Structure

The Houdini installation has the following structure:
- `/opt/houdini/bin`: Contains the main executables including `hrender`
- `/opt/houdini/dsolib`: Contains dynamic shared objects (plugins)
- `/opt/houdini/houdini`: Contains Houdini-specific files
- `/opt/houdini/toolkit`: Contains development tools

## VRay Directory Structure

The VRay installation has the following structure:
- `/opt/vray/bin`: Contains the main VRay executables
- `/opt/vray/vrayplugins`: Contains VRay plugins for Houdini
- `/opt/vray/vray/osl`: Contains Open Shading Language files

## Usage Instructions

### Running Houdini Renderer

```bash
docker run --rm keyshot-cin4d-houdini:latest houdini [options] [scene_file]
```

Common options:
- `-h`: Display help information
- `-i`: Information about the scene
- `-o`: Output file path

### Running VRay Renderer

```bash
docker run --rm keyshot-cin4d-houdini:latest vray [options] [scene_file]
```

Common options:
- `-help`: Display help information
- `-display`: Enable display output
- `-imgFile`: Specify output image file

## Common Issues and Solutions

### Missing Libraries
- Error: `cannot open shared object file: No such file or directory`
  - Solution: Install the missing library using `dnf install`

### License Issues
- Error: `No license found`
  - Solution: Ensure proper license setup or use the `-r` flag for non-commercial rendering

### Headless Environment
- Warning: Various GUI-related errors in a headless environment
  - Solution: These are expected in a Docker container without a GUI and don't affect command-line rendering

## Next Steps

To further improve the Houdini Docker container:

1. Add sample scenes for testing the rendering capabilities
2. Create examples of rendering commands and workflows
3. Add volume mounting instructions for input/output files
4. Configure VRay integration with Houdini
5. Set up proper license management for production use
6. Create a healthcheck to monitor the rendering services