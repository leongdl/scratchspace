The installer must be run using sudo.

Note:

Make sure that the install file is not located in root's home folder (/root) as this will give you permission errors during the install process.
Install the License Server component if:
installing for Houdini Indie or Houdini Apprentice.
the computer is a license server to serve licenses to client machines, or
a Workstation (nodelock, not using a remote license server) is installed.
If the computer is a client machine and will use a remote license server, you do not need to install the License Server component.
Download:

Download the latest Production or Daily build of Houdini.

To install:

Open a Terminal.
Unpack the downloaded tar.gz archive.
$ tar -xvf houdini-20.5.654-linux_x86_64_gcc11.2.tar.gz
// This should create a directory called houdini-20.5.654-linux_x86_64_gcc11.2
Go into the unpacked directory and run the houdini.install script using sudo.
$ cd houdini-20.5.654-linux_x86_64_gcc11.2
$ sudo ./houdini.install
Alternatively, you can also double click on the houdini.install file with your mouse. It will run the installer in a terminal.
HOUDINI 20.5.654 INSTALLATION	
Enter a number to toggle an item to be installed.	
INSTALL
1.	Houdini	yes
2.	Desktop Menus for Houdini	yes
3.	Symlinks in /usr/local/bin	no
4.	Symlink /opt/hfs/20.5 to install directory	yes
5.	License Server	no
6.	Avahi (Third-party)	no
7.	SideFx Labs	no
8.	Houdini Engine for Maya	no
9.	Houdini Engine for Unreal	no
10.	HQueue Server	no
11.	HQueue Client	no
D.	Change installation directory (/opt/hfs/XX.X.XXX)	
F.	Finished selections, proceed to next step	
Q.	Quit (no installation will  be attempted)	
4. If installing for a license server, or Houdini Apprentice or Houdini Indie, make sure to install the License Server component (option 5 in the image above) in the installer.
5. The licensing menu may appear during the installation process if no installed licenses can be detected.
* If you are installing Apprentice, choose "Install Houdini Apprentice license. * If you are installing a commercial product, choose I have a paid license for Houdini.
For more information about licensing Houdini please refer to Licensing a Houdini product

To launch Houdini from the Terminal, type the following:

$ cd /opt/hfs20.5
$ source houdini_setup
// This should setup the Houdini environment for you.
$ houdini


------
More data from Conda recipie: https://github.com/aws-deadline/deadline-cloud-samples/blob/mainline/conda_recipes/houdini-20.5/recipe/build.sh

INSTALLER=$SRC_DIR/installer/houdini.install
# date of the EULA agreement, not the current date
EULAdate=2021-10-13
$INSTALLER \
    --auto-install \
    --accept-EULA $EULAdate \
    --no-install-engine-maya \
    --no-install-engine-unity \
    --no-install-menus \
    --no-install-bin-symlink \
    --no-install-hfs-symlink \
    --no-install-license \
    --no-install-hqueue-server \
    --no-root-check \
    --make-dir $PREFIX/opt/houdini

HOUDINI_DIR=$PREFIX/opt/houdini