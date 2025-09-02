# Installation of RenderMan for Houdini

Last updated 20 May, 2025

For supported Houdini versions, please visit Installation and Licensing.
RenderMan for Houdini can be installed using the RenderMan Installer, which manages the downloading, installation, and licensing of the RenderMan Pro Server (the actual renderer) along with all bridge products.

## Package Installation
RenderMan for Houdini can be installed with a packages file, found in the RfH installation directory.

Copy the packages json file to one of the following locations for Houdini to find on startup. Advanced package instructions by SideFX are here.

- `$HOUDINI_USER_PREF_DIR/packages`
- `$HFS/packages`
- `$HSITE/houdinimajor.minor/packages` (for example, `$HSITE/houdini19.0/packages`)
- `$HOUDINI_PACKAGE_DIR`

Note that RenderMan only supports OCIO 2.2 so it is necessary to set OCIO to a supported config file when launching Houdini 20.5 otherwise Houdini will try to set OCIO to an unsupported 2.3 config file.

A simple way to do so is to add the following line to the package json file:
```json
{ "OCIO": "${RMANTREE}/lib/ocio/ACES-1.3/config.ocio" }
```

## Manual Installation 
The environment variable for RfH must be listed first in the houdini.env file. (Windows requires a semi-colon) For example:

```bash
HOUDINI_PATH=$RFHTREE/3.9/19.5.805:&
```

RenderMan for Houdini with Solaris requires an additional line in the configuration file to be able to render in-memory vdbs:

```bash
RMAN_PROCEDURALPATH = $RFHTREE/3.9/19.5.805/openvdb:&
```

RenderMan for Houdini on Windows requires an additional line in the configuration file:

```bash
PATH=$RMANTREE\bin;&
```


## Environment Configuration

After installing the plugin, Houdini requires a modification to the Houdini environment in your home directory to load the RenderMan plugin. Houdini specific environment variables can also be set in the houdini.env, found in the following locations for each operating system:

- **Windows**: `%HOME%\Documents\houdiniXX.X\houdini.env`
- **Mac**: `~/Library/Preferences/houdini/YY.Y/houdini.env`
- **Linux**: `~/houdiniZZ.Z/houdini.env`

**NOTE**: When you run a new version of Houdini for the first time, you may have to run it twice before the houdini.env files appear in the locations mentioned above, once created you can add the lines mentioned below.

You need to edit the houdini.env file with a text editor and place the following lines below in that file before you start Houdini. This only has to be done once for each new major version of Houdini that is being used.

## Examples

### Linux
Edit the file in: `$HOME/houdini19.5/houdini.env`:

```bash
RMANTREE=/opt/pixar/RenderManProServer-26.0
RFHTREE=/opt/pixar/RenderManForHoudini-26.0
RMAN_PROCEDURALPATH=$RFHTREE/3.9/19.5.805/openvdb:&
HOUDINI_PATH=$RFHTREE/3.9/19.5.805/:&
```

### Windows
Edit the file in: `\Users\myself\Documents\houdini19.5\houdini.env`:

**NOTE**: Windows uses a semi-colon instead of a colon to separate the HOUDINI_PATH!

```bash
RMANTREE="C:\Program Files\Pixar\RenderManProServer-26.0"
RFHTREE="C:\Program Files\Pixar\RenderManForHoudini-26.0"
RMAN_PROCEDURALPATH=$RFHTREE\3.9\19.5.805\openvdb;&
HOUDINI_PATH=$RFHTREE\3.9\19.5.805;&
PATH=$RMANTREE\bin;&
```

### macOS
Edit the file in: `/Users/myself/Library/Preferences/houdini/19.5/houdini.env`:

```bash
RMANTREE=/Applications/Pixar/RenderManProServer-26.0
RFHTREE=/Applications/Pixar/RenderManForHoudini-26.0
RMAN_PROCEDURALPATH=$RFHTREE/3.9/19.5.805/openvdb:&
HOUDINI_PATH=$RFHTREE/3.9/19.5.805:&
```
