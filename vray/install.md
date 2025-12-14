Skip to main content

Site logo


Navigated to page V-Ray Standalone - Chaos Docs

Portable Installation of V-Ray Standalone
Last updated 22 days ago
This page provides information on the V-Ray Standalone Portable Installation.

Please do not use multiple V-Ray installation methods at the same time. If you plan on creating a Portable V-Ray Standalone, make sure you have uninstalled any other V-Ray Standalone version.

 

Overview
The V-Ray Standalone installation file (.exe) can be unpacked and used as a portable version. Creating a Portable installation provides several advantages over the regular installer:

The Portable installation allows for setting a custom environment when starting each instance. To compare, running the regular installation multiple times overwrites the V-Ray environment variables.
The Portable installation can be used to run V-Ray and V-Ray Standalone from any location or even a network drive. That way, multiple users can start V-Ray and V-Ray Standalone using just a script that sets up the environment variables without the need to run local installations.
Upgrading a Portable installation is a lot easier too, as you don't need to run the installer on every user's computer.
The Portable installation allows for quick switching between different V-Ray Standalone versions without reinstalling it.
 

When using V-Ray from a Portable installation, the EULA needs to be accepted to start a render.

Please note that the Portable installation is derived from unpacking the V-ray Standalone installation file(.exe). It is not the same as a zip installation.

 

Required steps to run V-Ray Standalone
To create a Portable installation, you need to:

 

1. Download a V-Ray Standalone installation file. Click the button to do so.

 


 

2. Unpack the installation file. See the Unpack the installation file section of this page for more information.

3. Set up the environment variables needed to run V-Ray Standalone. See the Environment setup section of this page for more information.

4. Set up your license. Visit the Licensing section to find out how.

5. Run V-Ray Standalone.

 

Unpacking the installation file
NOTE that the cases here show example versions of V-Ray Standalone. The version you are using might differ.

Unpacking the installation creates folders in your specified location, which you can later use to install V-Ray Standalone on any computer and in any location you like. Here is a detailed step-by-step guide:

 



To unpack the executable version of the installer, open the Terminal. Type out: the location of the installer you just downloaded -unpackInstall=location where you wish to unpack. Alternatively, you can drag and drop the installer and folder into Terminal to insert their directories. Press Enter to run the command. It should look something like this:
1
/home/Username/Downloads/vraystd_adv_61003_centos7_clang-gcc-6.3 -unpackInstall=<chosen_location>
 

 

Environment setup
Before you run V-Ray Standalone, you need to set up an environment. There are some specific steps to consider. The license setup is the last requirement, as V-Ray needs to be instructed where to look for a valid license.

Please read the sections below for more information and examples.

The example directory and version names below are for V-Ray Standalone on Linux where vraystd_adv_60010_centos7_clang-gcc-6.3 has been unpacked into /home/Username/vray_builds/.

Here is a list of the environment variables and their description and examples. An example of a complete setup will be given further below.

OS

Action

Variable

Location

Description

Example

OS

Action

Variable

Location

Description

Example

Linux

Set

VRAY_OSL_PATH

/opensl

Required for the OSL definitions of the OSL plugin.

export VRAY_OSL_PATH=/home/Username/vray_builds/vray6xxxx_std/opensl

Linux

Extend

LD_LIBRARY_PATH

/lib

Required to run V-Ray itself.

export LD_LIBRARY_PATH=/home/Username/vray_builds/vray6xxxx_std/lib/:$LD_LIBRARY_PATH

Linux

Set

VRAY_AUTH_CLIENT_FILE_PATH

arbitrary location

Points V-Ray to a V-Ray license.

export VRAY_AUTH_CLIENT_FILE_PATH=<folder_containing_vrlclient.xml>

Since V-Ray 6, update 1, the VRAY_OSL_PATH variable has been deprecated and no longer needs to be set.

 

Tags
The [STDROOT] and [PLUGINS] tags in the script are normally replaced with their respective directories by the V-Ray installer. However, if you are using a version earlier than V-Ray 6, update 1, and performing a portable installation, it is necessary to manually replace these tags. The [STDROOT] tag needs to be replaced with the full path to the vray folder in the portable file. The [PLUGINS] tag needs to be replaced with the full path to the maya_vray folder in the portable file. The tags are located in the following files:

 

Linux and MacOS:

maya_vray/vray/VRay.app/Contents/MacOS/vray.bin

maya_vray/vray/VRay.app/Contents/MacOS/vrayserver

vray/vray_netinstall_client_setup.sh

vray/samples/appsdk/setenv39.sh

vray/bin/vraymayaserver.conf

vray/bin/registerVRayServerDaemon

vray/bin/initVRayServerDaemon

vray/bin/vraymayaserver.service

maya_vray/bin/plgparamsdata

Windows:

maya_vray/bin/plgparamsdata

 

If you want to use any additional tools like the standalone denoiser, or the VRIMG to OpenEXR converter, etc., then also add <unpacked_location>/vray/bin to the PATH environment variable.

Please note that by default the V-Ray installer will set the TdrLevel (that is GPU timeout detection and recovery) to 0 (disabled).

 

Notes

1.VRAY_AUTH_CLIENT_FILE_PATH needs to point to the folder that contains the vrlclient.xml  file that holds the V-Ray license server settings (IP address and port number). Alternatively, using the tool to set or change your license settings will create the vrlclient.xml file for you at a default location and there will be no need to explicitly define its location the VRAY_AUTH_CLIENT_FILE_PATH variable. However, it might be useful to use the variable to define per-user license settings.

Please note that this environment variable is optional. If nothing is specified, the default auth client file path is used. 

For the case where using the environment variable is the best option for you and you need to create the vrlclient.xml file manually, the example below shows what it should contain:

Example: vrlclient.xml
Please note that by default the V-Ray installer sets the TdrLevel (that is GPU timeout detection and recovery) to 8 (seconds of delay). Installing V-Ray from a portable installation may require the user to manually change this registry entry and should optionally have the full path to the registry.
V-Ray Standalone can not be ran if Microsoft Visual C++ Redistributable v143+ is not installed.
Chaos
            
© 2025 Chaos Software EOOD. All Rights reserved. Chaos®, V-Ray® and Phoenix FD® are registered trademarks of Chaos Software EOOD in Bulgaria and/or other countries.

Terms of use
Privacy policy
EULA
