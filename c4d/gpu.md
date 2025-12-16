Command-line Rendering and GPU Selection
When rendering from the command-line of your 3d app with Redshift, you can specify the GPU devices to use for the rendering job. When specifying the GPU devices from the command-line, the Redshift preferences.xml file is not updated, so running your 3d app in interactive mode will still use the GPU devices that you specified in the System tab of the Redshift render options.

Several render managers including Deadline and Royal Render natively support GPU selection when rendering with Redshift. Selecting only a subset of available GPUs for a job is useful for example to render multiple frames simultaneously on a single machine for optimal scaling.



Prerequisites
To render from the command-line you can use the CommandLine tool located in you Cinema 4D application installation folder. Alternatively the Cinema 4D application itself can also be used.



Syntax

Commandline.exe -redshift-gpu <device_id> -render c:\path\to\scene.c4d


Where <device_id> is the GPU device id you wish to render with.



Example
To render a scene located at c:\path\to\scene.c4d using only GPU device 1:




Commandline.exe -redshift-gpu 1 -render c:\path\to\scene.c4d


To render the same scene rendered using both GPU device 0 and 1:




Commandline.exe -redshift-gpu 0 -redshift-gpu 1 -render c:\path\to\scene.c4d


The CommandLine tool supports multiple parameters for customizing rendering (frame ranges, image output options etc.) For more details please consult the Cinema 4D and the "Command Line" section of the Cinema 4D documentation.



How do I determine my GPU device ids?
There are a number of ways to determine the device ids associated with each of your GPUs.

One option is to open prefences.xml from C:\ProgramData\Redshift in a text editor and inspect the value of "AllCudaDevices". For example:




<preference name="AllComputeDevices" type="string" value="0:Quadro K5000,1:Quadro 6000," />

In this case the Quadro K5000 is device 0, while the Quadro 6000 is device 1.

