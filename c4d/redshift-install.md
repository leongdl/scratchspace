Open topic with navigation
Installation > Installing Redshift on Linux
Installing Redshift on Linux
 

Important

On Linux, you only need the NVidia display driver. I.e. you do  not need to install any separate CUDA drivers/packages!

 

System Requirements
Please see the Redshift System Requirements Support page for the latest information.

 

Running the Redshift installer
The Redshift installer for Linux is distributed as a .run file. This is a self-extracting archive containing the Redshift binaries, data and scripts to assist in the installation.

To install Redshift, open a terminal, navigate to the directory where you downloaded the .run file and execute the .run file using sh as super user. This example is for version 1.2.97 of Redshift. Adjust the version number accordingly.

sudo sh ./redshift_v2.0.64_linux.run

The installer will extract the archive and launch the installation script automatically to guide you through the installation. First you will be presented with the Redshift Software License Agreement. You can scroll through the agreement using the spacebar. If you agree to the terms of the agreement, type 'accept' (no quotes) to proceed.

Please review the Redshift Software License Agreement carefully before continuing.By typing a ccept, you are agreeing to be bound by the terms of the agreement. If you agree with the terms and wish to proceed with the installation, type accept and hit Enter to continue.If you do not agree with the terms, you must not type accept and you must exit the installer (by typing quit or anything other than accept) and remove the installer from your system.

Next the installer will ask you to enter the path to which you want to install Redshift. The default path /usr/redshift is suitable for most installations, but you are free to install Redshift to another path if desired. Once you've entered your desired installation path, the installer will proceed by extracting the necessary Redshift binaries and data files.

When finished you will be notified to refer to /usr/redshift/redshift4maya/install.txt (adjust accordingly for custom installation locations) for some additional necessary steps that should be followed the first time Redshift is installed on a system in order to register Redshift with Maya.



Registering Redshift with Maya
The first time you install Redshift on a system, you will need to register Redshift with Maya so that Maya can correctly locate the redshift4maya plugin and script files.

This can be accomplished either by creating a Maya module file for Redshift, modifying the Maya.env file or by defining system environment variables. We recommend using a Maya module file as it requires the fewest steps as is the least prone to errors.  See the  Maya Plugin Configuration page for more details.

