https://help.maxon.net/c4d/en-us/#html/52193.html?Highlight=command%20line

Starting Cinema 4D via the Command Line
Cinema 4D can be started via the command line. This is useful if you want to control render functions using other software (e.g., render farm software). A Windows system is used in the example described below (references for Macintosh users are listed subsequently).

G

Enter the following to start Cinema 4D via the command line ( If a path or file name contains spaces it can help to enclose them in quotation marks):

c:\programs\\Cinema 4D\Commandline.exe

Tip:
C:\programs\\Cinema 4D\Cinema 4D.exe can also be used. However, Commandline.exe, which is installed in the installation directory s, is recommended because it also starts without the application interface and always leaves a console open.
For c:\Programme\\Cinema 4D\ enter your individual path to the executable file.


-render
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d

This command will render the scene hajopei.c4d, located in the c:\scenes directory. The render settings already defined in Cinema 4D will be used.


-take
Example: c:\Programme\\Cinema 4D\Commandline.exe -render c:\Szenen\hajopei.c4d -take front

This command renders a specific Take. In this example it's the Take named ,front’.


-frame
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d -frame 100 150 10

This command will render every 10th frame from frame 100 to 150. If 150 and 10 were not included in the command line, only frame 100 would be rendered. This command will override any scene settings.


-oimage
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d -oimage d:\images\framename

This will overwrite the save path for the scene file hajopei.c4d and render to the d:\images directory. The files will be named according to framename. Sequential frame numbers will be added automatically.


-omultipass
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d -omultipass c:\mp\passes.psd

This will overwrite the scene's Multi-Pass path and save the Multi-Pass to the c:\mp\ directory. Sequential frame numbers and Multi-Pass names will be added automatically.


-oformat
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d -oformat JPG


-oformat JPG
The output format defined in the scene file itself can be replaced with one of the following formats: TIFF, TGA, BMP, IFF, JPG, PICT, PSE, RLA, RPF, B3D, HDR, EXR, PNG, PSP.


-oresolution
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d -oresolution 800 600

This will overwrite the render size as defined in the hajopei.c4d scene file. In this case the render output will have a resolution of 800 x 600.


-threads
Example: c:\programs\\Cinema 4D\Commandline.exe -render c:\scenes\hajopei.c4d -threads 2

This defines the number of threads. 0 is the optimal number of threads.


g_logfile=[string]
Example: c:\Programs\\Cinema 4D\Commandline.exe - render c\Scenes\hajopei.c4d g_logfile= c:\Report.txt]

All information regarding render progress will be saved in a file on the hard drive (in this case Report.txt on your c: drive).

The following commands, with the exception of -help, are less useful when using the Commandline option and only have a function if the Cinema 4D executable file iw used with the options described.


-help
Launches a brief description of supported commands


-minimalviewport
Cinema 4D starts with minimum Viewport options.


-nogui
Starts Cinema 4D without a GUI (interface).

Tip:
Make sure that this command comes first. Otherwise, new window may still be opened.

-title
Windows only: c:\programs\\Cinema 4D\Cinema 4D.exe -title Name

This command assigns a name to a Cinema 4D window. This name will be displayed at the top left of the Cinema 4D window and in the task bar. This makes locating one of several open instances of Cinema 4D much easier using Alt+tab.


-layout
Example: c:\Programme\\Cinema 4D\Cinema 4D.exe -layout c:\Programme\\Cinema 4D\library\layout\Modeling.l4d

Use this command to load a specific layout when starting Cinema 4D.


-license [ip [port]]
Example: c:\Programs\\Cinema 4D\CNEMA 4D.exe -licence 192.168.30.15 5235

This lets you start program instances that access the License Server (if the server has also been started as a command line instance) or the RLM server (enter the host name instead of the IP address).


Macintosh Systems
The syntax for paths on Macs looks somewhat different. The executable Cinema 4D file can be launched directly from a console window:

1. Right-click on the Cinema 4D.app start-up file in your installation directory and select Show Package Contents.

2. Switch to the contents/macOS directory.

3. Drag the Cinema 4D file into the terminal window. The correct path will automatically be used.

4. Enter the desired commands (e.g., -render, -nogui, etc.)

5. Drag the scene file to be rendered into the terminal window. Make sure the path is correct.