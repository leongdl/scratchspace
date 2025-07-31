Unpacking the installation file
Unpack the installation into a suitable location, which you can later use to run V-Ray on any computer. Here is a detailed step-by-step guide:



Windows
Linux
macOS

Download the V-Ray installer.
Open a Terminal. Type out: the location of the installer that you just downloaded -unpackInstall= location where you wish to unpack. Alternatively, you can drag and drop the installer and a target folder for unpacking into the Terminal to insert their directories. Press Enter to run the command. As an example, you can create a new folder called vray_builds to hold all portable V-Ray builds. Then, you can make other sub-folders and name them according to the V-Ray build version, for example vray_60002_maya2023 . It should look something like this:

/home/user/Downloads/vray_adv_60002_maya2023_centos7 -unpackInstall=/opt/vray_builds
After unpacking the installation, your folder structure should look like this:


/opt/vray_builds/
├── vray_60002_maya2023\
│ ├── maya_root\
│ ├── maya_vray\
│ └── vray\



Here is an example with two different V-Ray 6 builds for Maya 2023 - each can be deployed with its own shell script and environment.

/opt/vray_builds/
├── vray_60002_maya2023\
│ ├── maya_root\
│ ├── maya_vray\
│ └── vray\
├── vray_60010_maya2023\
│ ├── maya_root\
│ ├── maya_vray\
│ └── vray\



The  /opt/vray_builds  location is simply an example. The Portable Installation can be unpacked anywhere.
Set the necessary environment variables into a new Terminal and run V-Ray for Maya or V-Ray Standalone.


 



Setup for Maya
The easiest way to deploy V-Ray is to use the V-Ray module file that comes with the Portable Installation.

The V-Ray module is located in <unpacked location>/maya_root/modules. It contains all the variables needed to run V-Ray for Maya. It also has a readme part with instructions on how to set the environment using a module file. It can be set using one of two ways:



Recommended: Extend the MAYA_MODULE_PATH variable to contain the folder with the module file. Open Command Prompt or Terminal and type



Windows
Linux
macOS
The example directory and version names below are for V-Ray 6 for Maya 2023 on Linux where vray_adv_60002_maya2023_centos7 has been unpacked into /opt/vray_builds/vray_60002_maya2023/.

Here is a list of the environment variables and their descriptions and examples. An example of a complete setup will be given further below.

export MAYA_MODULE_PATH=/opt/vray_builds/vray_60002_maya2023/maya_root/modules:$MAYA_MODULE_PATH

Alternative: Move the module file to Maya's module folders.
You will need to edit the file to replace "../../maya_vray" with the full path to the maya_vray directory.
Then move the module file to the respective Maya versions' modules location. Here's the locations for Maya 2023:


Windows
Linux
macOS
/usr/autodesk/modules/maya/2023




A truly portable installation can be deployed with a .bat (Windows) or shell script (Linux, macOS) that extends MAYA_MODULE_PATH and starts Maya. You can have multiple scripts, each starting Maya with the module for a different V-Ray version.

Moving the module file inside Maya's folders is useful for a quick setup, but not truly portable.




License setup
1. Before you run V-Ray, make sure that it can find a license.

You can set up your license using the tool to set or change your license settings.

Alternatively, you can use the VRAY_AUTH_CLIENT_FILE_PATH* environment variable and point it to the folder containing a vrlclient.xml file that holds the V-Ray license server settings (IP address and port number).

When using the environment variable is the best option for you and you need to create the vrlclient.xml file manually, the example below shows what it should contain:

Example: vrlclient.xml
 

Setup for V-Ray Standalone
Environment variables

The portable install can also be used to run only V-Ray Standalone without running V-Ray for Maya. In this case, the number of environment variables to set is reduced.

The list of variables to set requires unpacking the same installation build. Read the Unpacking the installation file section for more details.

Before you run V-Ray, make sure that it can find a license. See the License setup section of this page.

Windows
Linux
macOS
The example directory and version names below are for V-Ray 6 for Maya 2023 on Linux where vray_adv_60002_maya2023_centos7 has been unpacked into /opt/vray_builds/vray_60002_maya2023/.

Here is a list of the environment variables and their descriptions and examples. An example of a complete setup will be given further below.


Linux	Extend	
VRAY_FOR_MAYAnnnn_PLUGINS

<unpacked_location>/maya_vray/vrayplugins

Needed for V-Ray Standalone.	export VRAY_FOR_MAYA2023_PLUGINS=/opt/vray_builds/vray_60002_maya2023/maya_vray/vrayplugins:$VRAY_FOR_MAYA2023_PLUGINS
Linux	Set	VRAY_AUTH_CLIENT_FILE_PATH 1	arbitrary location	Points V-Ray to a V-Ray license.	export VRAY_AUTH_CLIENT_FILE_PATH=<folder_containing_vrlclient.xml>




Legacy Variables for versions prior to V-Ray 6, update 1


Tags
The [STDROOT] and [PLUGINS] tags in the script are typically replaced with their respective directories by the V-Ray installer. However, if you are using a version earlier than V-Ray 6, update 1, and performing a portable installation, you need to manually replace these tags. The [STDROOT] tag needs to be replaced with the full path to the vray folder in the portable file. The [PLUGINS] tag needs to be replaced with the full path to the maya_vray folder in the portable file. The tags are located in the following files:



Linux and macOS:

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