
The installation bundle installs the entire Nuke family, including Hiero and HieroPlayer, and icons for the various components appear in your installation folder.

Note:  Some modern anti-virus software may wrongly assume that certain files in the installer are suspicious. Examples of these files include libnuke-12.0.0.so and geolib-runtime-prof.so. If you have trouble installing the application on your machine, try disabling your anti-virus software before installation. Don't forget to restart your anti-virus software after installation.

Download the installation file from our website at https://www.foundry.com/products/nuke/download
Extract the application from the .tgz archive and then execute the following terminal command, replacing <version number> with the current version:
sudo ./Nuke<version number>-linux-x86_64.run

Note:  If you leave out sudo from the terminal command, you need to ensure that you have sufficient permissions to install the application under your current working directory.

After the application files have been installed, the installer also runs a post-installation script that creates the following directory:
/usr/local/foundry/RLM

If you don’t have sufficient permissions on the /usr/local folder for this directory to be created, the post-installation script prompts you for your sudo password as necessary.

The installer displays the End User Licensing Agreement (EULA) and prompts you to accept it.

If you agree with the EULA, enter y and press Return to continue. (If you don’t agree with the EULA and press N instead, the installation is canceled.)
Note:  You can skip the EULA step using the --accept-foundry-eula option, which means you agree to the terms of the EULA:
sudo ./Nuke<version number>-linux-x86_64.run --accept-foundry-eula
To see the EULA, please refer to https://www.foundry.com/eula.

By default, Nuke is installed in the current working directory.

Proceed with Launching on Linux.
Tip:  You can also use the following options after the terminal command when installing the application:
--prefix=/home/biff/nuke_installs
Specifies a different install directory, in this case, nuke_installs.
--help
Displays additional installer options.

Nuke License environment variable locally is 
foundry_LICENSE=4101@127.0.0.1


------
Nuke command line web page:
On Linux
Open a command line prompt and change directory as follows:

cd /usr/local/Nuke16.0v4/

To launch Nuke, type this command:

./Nuke16.0

Alternatively, you can set an alias to point to Nuke and then you can launch Nuke from any directory. The procedure for this depends on what your default shell is. To get the name of the shell you are using, launch Terminal and enter echo $SHELL.

If you are using a bash shell, enter:

alias nuke='/usr/local/Nuke16.0v4/Nuke16.0'

Alternatively, if you are using a tcsh shell, enter:

alias nuke=/usr/local/Nuke16.0v4/Nuke16.0

If you want to alias NukeX, enter:

alias NukeX=/usr/local/Nuke16.0v4/Nuke16.0 --nukex

If you want to alias Nuke Studio, enter:

alias nukes=/usr/local/Nuke16.0v4/Nuke16.0 --studio

Tip:  You can add aliases to a .cshrc or .bashrc file in your home directory so that they are activated each time you open a shell. See your Systems Administrator for help setting this up.

Using command line Flags
Now you can start experimenting with command line flags on launching Nuke. Here’s one that displays the version number and build date.

nuke -version

If you have an .nk script, you can render it on the command line without opening the GUI version. Here’s an example that renders a hundred frames of a Nuke script:

nuke -F 1-100 -x myscript.nk

Note how you can use the -F switch on the command line to indicate a frame range, separating the starting and ending frames with a dash.

Note:  We recommend that you use the -F switch whenever defining a frame range on the command line, which must precede the script name argument.
However, for backwards compatibility, you can also use the old syntax. To do so, place the frame range at the end of the command and use a comma to separate the starting and ending frames. For example:
nuke -x myscript.nk 1,100

To display a list of command line flags (switches) available to you, use the following command:

nuke -help

Here’s that list of command line flags in a table:

Switch/Flag

Action

-a

Formats default to anamorphic.

-c size (k, M, or G)

Limit the cache memory usage, where size equals a number in bytes. You can specify a different unit by appending k (kilobytes), M (megabytes), or G (gigabytes) after size.

Note:  Nuke's actual cache memory usage is determined by which ever is smaller: the size value passed into this flag, or the "comp cache size (%)" set in Preferences > Performance > Caching. As such, this flag can't be used to increase Nuke's cache size above the "comp cache size (%)".

--cont

Nuke attempts to render subsequent frames in the specified range after an error. When --cont is not specified, rendering stops when an error is encountered.

--crashhandling 1

--crashhandling 0

Breakpad crash reporting allows you to submit crash dumps to Foundry in the unlikely event of a crash. By default, crash reporting is enabled in GUI mode and disabled in terminal mode.

Use --crashhandling 1 to enable crash reporting in both GUI and terminal mode.

Use --crashhandling 0 to disable crash reporting in both GUI and terminal mode.

Tip:  You can also use the NUKE_CRASH_HANDLING environment variable to control crash handling. See Environment Variables for more information.

-d <x server name>

This allows Nuke to be viewed on one machine while run on another. (Linux only and requires some setting up to allow remote access to the X Server on the target machine).

-f

Open Nuke script at full resolution. Scripts that have been saved displaying proxy images can be opened to show the full resolution image using this flag. See also -p.

-F

Frame numbers to execute the script for. All -F arguments must precede the script name argument. Here are some examples:

• -F 3 indicates frame 3.

• -F 1-10 indicates frames 1, 2, 3, 4, 5, 6, 7, 8, 9, and 10.

• -F 1-10x2 indicates frames 1, 3, 5, 7, and 9.

You can also use multiple frame ranges:

nuke -F 1-5 -F 10 -F 30-50x2 -x myscript.nk

--gpu ARG

When set, enables GPU usage in terminal mode with an optional GPU index argument, which defaults to 0. Use --gpulist to display the selectable GPUs.

Note:   Overrides the GPU set in Preferences > Performance > Hardware when run in interactive mode.

--gpulist

Prints the selectable GPUs and their corresponding index for use with the --gpu ARG option.

-h

Display command line help.

-help

Display command line help.

-i

Use an interactive (nuke_i) RLM license key. This flag is used in conjunction with background rendering scripts using -x. By default -x uses a nuke_r license key, but -xi background renders using a nuke_i license key.

Note:  If you still use FLEXlm licenses and you're interested in making a move to RLM licensing, please contact sales@foundry.com to obtain a replacement license.

-l

New read or write nodes have the colorspace set to linear rather than default.

-m #

Set the number of threads to the value specified by #.

--multigpu

If have multiple GPUs of the same type installed, you can enable this preference to share work between the available GPUs for extra processing speed. This is a global preference and is applied to all GPU enabled nodes.

Note:  For more information on GPU support, see the Release Notes for your version of Nuke.

-n

Open script without postage stamps on nodes.

--nocrashprompt

When crash handling is enabled in GUI mode, submit crash reports automatically without displaying a crash reporter dialog.

Tip:  You can also use the NUKE_NO_CRASH_PROMPT environment variable to control the crash prompt. See Environment Variables for more information.

--nukeassist

Launch Nuke Assist, which is licensed as part of a NukeX Maintenance package and is intended for use as a workstation for artists performing painting, rotoscoping, and tracking. Two complimentary licenses are included with every NukeX license.

-p

Open Nuke script at proxy resolution. Scripts that have been saved displaying full resolution images can be opened to show the proxy resolution image using this flag. See also -f.

-P

Measure your nodes’ performance metrics and show them in the Node Graph. See Using Performance Timing for more information.

--pause

Initial Viewers in the script specified on the command line should be paused.

-Pf <filename>

Measure your nodes’ performance metrics and write them to an XML file at render time. See Using Performance Timing for more information.

--nc

Runs Nuke in Nuke Non-commercial mode. See About Nuke Non-commercial for more information.

--priority p

Runs Nuke with a different priority, you can choose from:

• high (only available to the super user on Linux/OS X)

• medium

• low

--python-no-root-knobdefaults

Prevents the application of knob defaults to the root node when executing a Python script.

-q

Quiet mode. This stops non-essential printing to the command-line and suppresses information pop-ups, such as loading autosaved scripts and local changes to LiveGroups.

--remap

Allows you to remap file paths in order to easily share Nuke projects across different operating systems. This is the command line equivalent of setting the Path Remaps control in the Preferences dialog.

The --remap flag takes a comma-separated list of paths as an argument. The paths are arranged in pairs where the first path of each pair maps to the second path of each pair. For example, if you use:

nuke -t --remap "X:/path,Y:,A:,B:/anotherpath"

• Any paths starting with X:/path are converted to start with Y:

• Any paths starting with A: are converted to start with B:/anotherpath

The --remap flag throws an error if:

• it is defined when starting GUI mode, that is, without -x or -t

• the paths do not pair up. For example, if you use:

nuke -t --remap "X:/path,Y:,A:"

A: does not map to anything, and an error is produced.

The --remap flag gives a warning (but does not error) if you give it no paths. For example:

nuke -t --remap ""

Note:  Note that the mappings are only applied to the Nuke session that is being started. They do not affect the Preferences.nk file used by the GUI.

-s #

Sets the stack size per thread, in bytes. The default value is 16777216 (16 MB). The smallest allowed value is 1048576 (1 MB).

None of Nuke's default nodes require more than the default memory stack value, but if you have written a custom node that requests a large stack from the memory buffer, increasing the stack size can prevent stack overflow errors.

--safe

Running Nuke in safe mode stops the following loading at startup:

• Any scripts or plug-ins in ~/.nuke

• Any scripts or plug-ins in $NUKE_PATH or %NUKE_PATH%

• Any OFX plug-in (including FurnaceCore)

--sro

Forces Nuke to obey the render order of Write nodes so that Read nodes can use files created by earlier Write nodes.

-t

Terminal mode (without GUI). This allows you to enter Python commands without launching the GUI. A >>> command prompt is displayed during this mode. Enter quit() to exit this mode and return to the shell prompt. This mode uses a nuke_r license key by default, but you can get it to use a nuke_i key by using the -ti flag combo.

--tg

Terminal Mode. This also starts a QApplication so that PySide/PyQt can be used. This mode uses an interactive license, and on Linux requires an XWindows display session.

--topdown

Enables the new top-down rendering project setting to render the full frame at the cost of more memory. Although top-down rendering produces the full frame faster, it disables progressive rendering and uses more memory. You may want to use the classic method if you're only interested in the first few scan lines in the Viewer.

Note:  The render mode is only saved as part of the script if you set render mode to top-down in the Project Settings. This ensures that the chosen render method is used the next time the script is opened. Using the --topdown command line argument does not save the render mode in the script.

-V level

Verbose mode. In the terminal, you’ll see explicit commands as each action is performed in Nuke. Specify the level to print more in the Terminal, select from:

• 0 (not verbose)

• 1 (outputs Nuke script load and save)

• 2 (outputs loading plug-ins, Python, Tcl, Nuke scripts, progress and buffer reports)

-v

This command displays an image file inside a Nuke Viewer. Here’s an example:

nuke -v image.tif

--view v

Only execute the specified views. For multiple views, use a comma separated list:

left,right

--version

Display the version information in the shell.

--workspace arg

Launch Nuke and activate the specified workspace automatically. Any named layout specified in the Workspace dropdown is valid, including custom workspaces. For example:

--workspace Compositing

--workspace "Monitor Out"

--workspace MySetup

Tip:  If the workspace name contains a space, you may need to add quotes around the name.

-x

eXecute mode. Takes a Nuke script and renders all active Write nodes.

Note:  Nuke Non-commercial is restricted to encrypted .nknc scripts with -x from the command line, that is, using the syntax:
nuke -x myscript.nknc

This mode uses a nuke_r license key. To use a nuke_i license key, use -xi. This is the syntax:

nuke -xi myscript.nk

On Windows, you can press Ctrl+Break to cancel a render without exiting if a render is active, or exit if not. Ctrl/Cmd+C exits immediately.

On Mac and Linux, Ctrl/Cmd+C always exits.

Note:  If you still use FLEXlm licenses and you're interested in making a move to RLM licensing, please contact sales@foundry.com to obtain a replacement license.

-X node

Render only the Write node specified by node.

--

End switches, allowing script to start with a dash or be just - to read from stdin

General syntax
This is the general syntax for using these options when launching Nuke at the command prompt:

nuke <switches> <script> <argv> <ranges>

<switches> - modifies the behavior of Nuke when run from the command line. A list of switches is given in the table above. These are sometimes called flags.

<script> - the name of the Nuke script.

<argv> - an optional argument that can be used in Nuke. See the example below.

<ranges> - this is the frame range you want rendering.

Examples
Let’s consider some practical examples.

To launch Nuke and open a script.

nuke myscript.nk

Crazy I know, but I’ve called my script, -myscript.nk, and the hyphen at the start of the filename has confused Nuke. To get round this if you don’t want to rename your file use the double hyphen syntax:

nuke -- -myscript.nk

To display an image:

nuke -v polarbear.tif

To display several images:

nuke -v polarbear.tif whiteflower.psd mountains.cin

To display an image sequence (taxi.0001.tif, taxi.0002.tif,...,taxi.0050.tif):

nuke -v taxi.####.tif 1-50

To render frame 5 of a Nuke script:

nuke -F 5 -x myscript.nk

To render frames 30 to 50 of a Nuke script:

nuke -F 30-50 -x myscript.nk

To render two frame ranges, 10-20 and 34-60, of a Nuke script:

nuke -F 10-20 -F 34-60 -x myscript.nk

To render every tenth frame of a 50 frame sequence of a Nuke script:

nuke -F 1-50x10 -x myscript.nk

This renders frames 1, 11, 21, 31, 41.

In a script with two write nodes called WriteBlur and WriteInvert this command just renders frames 1 to 20 from the WriteBlur node:

nuke -X WriteBlur myscript.nk 1-20

Using [argv 0]
Let’s use [argv] to vary the output file name. Launch the GUI version of Nuke and create a node tree that puts a checker into a Write node. Open the write node property panel by double clicking on it and in the file text field enter this filename:

[argv 0].####.tif

Save the script and quit Nuke. On the command line type:

nuke -x myscript.nk mychecker 1-5

This renders 5 frames (mychecker.0001.tif, mychecker.0002.tif, etc.).

You can add another variable to control the output image file type. The file text field needs this:

[argv 0].####.[argv 1]

and then render the script using this command:

nuke -x myscript.nk mychecker cin 1-5

to get mychecker.0001.cin, mychecker.0002.cin, etc.

The <argv> string can be any [argv n] expression to provide variable arguments to the script. These must be placed between the <script> and the <ranges> on the command line. You can include multiple expressions, but each must begin with a non-numeric character to avoid confusion with the frame range control. For more information on expressions, see Expressions.

Using Python to convert TIFFs to JPEGs
This command line method converts 5 TIFF frames to JPEG.

nuke -t

>>> r = nuke.nodes.Read(file = ”myimage.####.tif”)

>>> w = nuke.nodes.Write(file = ”myimage.####.jpg”)

>>> w.setInput( 0, r )

>>> nuke.execute(“Write1”, 1,5)

>>> quit()

It’s a bit tedious typing these commands in line by line. So let’s put them in a text file called imageconvert.py and get Nuke to execute the Python script.

cat imageconvert.py

r = nuke.nodes.Read(file = ”myimage.####.tif”)

w = nuke.nodes.Write(file = ”myimage.####.jpg”)

w.setInput( 0, r )

nuke.execute(“Write1”, 1,5)

nuke -t < imageconvert.py

You can also pass in the Python script as a command line parameter. Doing this allows you to enter additional parameters after the script name to pass into your script. When you do so, note that sys.argv[0] is the name of the Python script being executed, and argv[1:] are the other parameters you passed in. One example of this is below. See the standard Python module optparse for other ways to parse parameters.

cat imageconvertwithargs.py

import sys

r = nuke.nodes.Read(file = sys.argv[1])

w = nuke.nodes.Write(file = sys.argv[2])

w.setInput(0, r)

nuke.execute("Write1", 1, 5)

nuke -t imageconvertwithargs.py myimage.####.tif myimage.####.jpg

