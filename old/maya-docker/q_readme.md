### What was added to the Dockerfile:

1. Redshift Installer Integration:
   • Copied the redshift_2025.5.0_1853528846_linux_x64.run installer into the container
   • Executed it with --accept --quiet --nox11 flags for automated installation
   • Cleaned up the installer file after installation

2. Maya 2025 Integration:
   • Created proper directory structure (/root/maya/modules, /root/maya/2025, /root/redshift)
   • Generated a custom redshift4maya.mod file specifically configured for Maya 2025
   • Copied redshiftRenderer.xml to Maya's renderer description directory for command-line rendering support

3. Environment Configuration:
   • Set REDSHIFT_COREDATAPATH=/usr/redshift
   • Set REDSHIFT_LOCALDATAPATH=/root/redshift
   • Configured proper plugin paths for Maya 2025

### Key Features of the Final Image:

• **Image**: mottosso/maya:2025-redshift (14.9GB)
• **Maya 2025**: Full installation with all components
• **Redshift 2025.5.0**: GPU-accelerated renderer fully integrated
• **Module System**: Properly configured for automatic loading
• **Command-line Support**: Ready for batch rendering
• **Headless Operation**: Configured with Xvfb for server environments

### Usage:

bash
# Run Maya with Redshift
docker run -ti --rm mottosso/maya:2025-redshift

# Run with GPU support (if available)
docker run -ti --rm --gpus all mottosso/maya:2025-redshift

# Mount working directory
docker run -ti --rm -v $(pwd):/workspace mottosso/maya:2025-redshift

# Start a bash
docker run -ti --rm mottosso/maya:2025-redshift /bin/bash

The image is now ready for production use with both Maya 2025 and Redshift 2025.5.0 fully configured and integrated!


## Available Commands in the Container:

You can now use these commands inside the container:

bash
# Maya Python interpreter
mayapy

# Maya batch mode
maya -batch

# Check Maya version
maya -v

# List Maya plugins
maya -batch -command "loadPlugin -a redshift4maya; pluginInfo -q -listPlugins"

# Check Redshift installation
ls /usr/redshift/

# Check Redshift module
cat ~/maya/modules/redshift4maya.mod

# Start Maya with GUI (if X11 forwarding is set up)
maya

# Check environment variables
env | grep -E "(MAYA|REDSHIFT)"


The container is ready for Maya and Redshift operations! The virtual display (Xvfb) is running on :99 which allows headless rendering operations.

To start a new interactive session, you can run:
bash
docker run -ti --rm mottosso/maya:2025-redshift /bin/bash
