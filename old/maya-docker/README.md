[![](https://images.microbadger.com/badges/image/mottosso/maya.svg)](https://microbadger.com/images/mottosso/maya "Get your own image badge on microbadger.com")

# Supported tags

- `2013sp1`, `2013sp2`, `2014sp1`, `2014sp2`, `2014sp3`, `2014sp4`, `2015sp1`, `2015sp2`, `2015sp3`, `2015sp4`, `2015sp5`, `2015sp6`, `2016sp1`, `2017`, `2018`, `2018.7`, `2019`, `2019.3`, `2020`, `2020sp1`, `2022`, `2022.1`, `2023`, `2024` and `2025`.
- `vray-7.10.00`: Maya 2025 with V-Ray Advanced 7.10.00, Redshift, Ornatrix, SpeedTree, and Arnold.

For more information about this image and its history, please see its the [GitHub repository][1].

[1]: https://github.com/mottosso/docker-maya/wiki

# Usage

To use this image and any of it's supported tags, use `docker run`.

```bash
$ docker run -ti --rm mottosso/maya
```

Without a "tag", this would download the latest available image of Maya. You can explicitly specify a version with a tag.


```bash
$ docker run -ti --rm mottosso/maya:2022
```

Images occupy around **5 gb** of virtual disk space once installed, and about **1.5 gb** of bandwidth to download.

**Example**

This example will run the latest available version of Maya, create a new scene and save it in your current working directory.

```bash
$ docker run -ti -v $(pwd):/root/workdir --rm mottosso/maya
$ mayapy
>>> from maya import standalone, cmds
>>> standalone.initialize()
>>> cmds.file(new=True)
>>> cmds.polySphere(radius=2)
>>> cmds.file(rename="my_scene.ma")
>>> cmds.file(save=True, type="mayaAscii")
>>> exit()
$ cp /root/maya/projects/default/scenes/my_scene.ma workdir/my_scene.ma
$ exit
$ cat my_scene.ma
```

# What's in this image?

This image builds on [mayabase-centos][2] which has the following software installed.

- [git](https://git-scm.com/)
- [pip](https://pip.pypa.io/en/stable/)

Each tag represents a particular version of Maya, such as 2016 SP1. In this image, `mayapy` is an alias to `maya/bin/mayapy` which has the following Python packages installed via `pip`.

- [nose](http://nose.readthedocs.org/en/latest/testing.html)

[2]: https://registry.hub.docker.com/u/mottosso/mayabase-centos/

# User Feedback

### Documentation

Documentation for this image is stored in the [GitHub wiki][1] for this project.

### Issues

If you have any problems with or questions about this image, please contact me through a [GitHub issue][3].

[3]: https://github.com/mottosso/docker-maya/issues

### Contributing

You are invited to contribute new features, fixes, or updates, large or small; I'm always thrilled to receive pull requests, and do my best to process them as fast as I can.

Before you start to code, we recommend discussing your plans through a GitHub issue, especially for more ambitious contributions. This gives other contributors a chance to point you in the right direction, give you feedback on your design, and help you find out if someone else is working on the same thing.
# Maya 2025 + V-Ray + Redshift + Ornatrix + SpeedTree Docker Container

## Overview
This Docker container includes a complete 3D production environment with Maya 2025, V-Ray Advanced 7.10.00, Redshift rendering, Ornatrix hair/fur simulation, and SpeedTree vegetation modeling.

## Software Stack
- **Maya 2025**: Fully functional 3D software
- **V-Ray Advanced 7.10.00**: Production renderer with Maya integration
- **Redshift 2025.5.0**: GPU rendering engine with Maya integration
- **Ornatrix Maya 2025 v5.1.2.36369**: Hair/fur simulation plugin (Demo version)
- **SpeedTree Modeler v10.0.1**: Vegetation modeling software
- **Arnold (MtoA)**: Additional renderer included with Maya

## Key Locations
```
/usr/autodesk/maya/                           # Maya 2025
/usr/autodesk/vray4maya2025/                  # V-Ray
/usr/redshift/redshift4maya                   # Redshift
/usr/autodesk/modules/maya/2025/OrnatrixMaya2025  # Ornatrix
/opt/SpeedTree/SpeedTree_Modeler_v10.0.1/    # SpeedTree
```

## Environment Variables
```bash
MAYA_LOCATION=/usr/autodesk/maya/
MAYA_MODULE_PATH=/usr/autodesk/vray4maya2025/maya_root/modules
VRAY_FOR_MAYA2025_PLUGINS=/usr/autodesk/vray4maya2025/maya_vray/vrayplugins
VRAY_OSL_PATH=/usr/autodesk/vray4maya2025/vray/opensl
REDSHIFT_COREDATAPATH=/usr/redshift
SPEEDTREE_HOME=/opt/SpeedTree/SpeedTree_Modeler_v10.0.1
```

## Verification Commands
```bash
# Maya
maya -batch -command "about -version"

# V-Ray
maya -batch -command "loadPlugin vrayformaya; pluginInfo -query -version vrayformaya"

# Redshift
maya -batch -command "loadPlugin redshift4maya; pluginInfo -query -version redshift4maya"

# Ornatrix
maya -batch -command "loadPlugin Ornatrix; pluginInfo -query -version Ornatrix"

# SpeedTree (with xcb backend)
export QT_QPA_PLATFORM=xcb
/opt/SpeedTree/SpeedTree_Modeler_v10.0.1/startSpeedTreeModeler.sh
```

## Docker Usage
```bash
# Interactive shell
docker run -it --rm maya-vray /bin/bash

# Render with V-Ray
docker run --rm -v $(pwd):/work -w /work -e VRAY_AUTH_CLIENT_FILE_PATH -e VRAY_AUTH_CLIENT_SETTINGS maya-vray /usr/autodesk/maya/bin/Render -r vray -rd /work -im output_image /work/scene.ma

# Render with Redshift
docker run --rm -v $(pwd):/work -w /work -e redshift_LICENSE maya-vray /usr/autodesk/maya/bin/Render -r redshift -rd /work -im output_image /work/scene.ma

# Render with Arnold
docker run --rm -v $(pwd):/work -w /work -e ADSKFLEX_LICENSE_FILE maya-vray /usr/autodesk/maya/bin/Render -r arnold -rd /work -im output_image /work/scene.ma
```

## License Configuration

### V-Ray License
V-Ray requires a license server configuration. You can pass the license information to the container using the following environment variables:

- `VRAY_AUTH_CLIENT_FILE_PATH`: Path to the directory containing the vrlclient.xml file
- `VRAY_AUTH_CLIENT_SETTINGS`: Additional V-Ray license settings

Example:
```bash
docker run --rm -e VRAY_AUTH_CLIENT_FILE_PATH=/path/to/license -v /path/to/license:/path/to/license maya-vray /bin/bash
```

## Troubleshooting

### Common V-Ray Issues

1. **License Server Connection**
   - Ensure the license server is accessible from the container
   - Check that the vrlclient.xml file is correctly configured
   - Verify network connectivity between the container and license server

2. **Plugin Loading Failures**
   - Verify that the V-Ray plugin is correctly installed
   - Check the Maya module path includes the V-Ray modules directory
   - Examine Maya's plugin loading logs for errors

3. **Renderer Selection**
   - If you have multiple renderers installed, ensure you're explicitly selecting V-Ray
   - Set the renderer using: `setAttr "defaultRenderGlobals.currentRenderer" -type "string" "vray"`

4. **Rendering Issues**
   - For headless rendering, ensure the scene is properly configured for batch rendering
   - Check that all paths in the scene are relative or accessible within the container