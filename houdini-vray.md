Installing V-Ray from Zip
V-Ray for Houdini can be downloaded from the V-Ray | Downloads section of the Chaos Group website (please make sure you use your login credentials to ensure access to the download links). It's recommended that you make sure your computer meets the System Requirements for running Houdini with V-Ray before installing V-Ray.

Under the hood, the V-Ray installation relies on the Houdini 3-rd party plugins package system. Houdini's packages are .json files that specify the location of custom modules. For more information, please refer to the documentation on the SideFX website.

The "vray_for_houdini.json" package that is used to load V-Ray when Houdini is started is placed under "$HFS/packages" (e.g. "C:\Program Files\Side Effects Software\Houdini 18.0.532\packages" for Windows) when running the installer. You may set things up differently depending on your studio pipeline.

By default, when using the installer, the location of V-Ray itself is "C:\Program Files\Chaos Group\V-Ray". Just as with the "vray_for_houdini.json", V-Ray itself can be placed anywhere on disk. As long as the "INSTALL_ROOT" variable in the json file points to a valid location, Houdini should be able to find the required modules to load V-Ray.

Example JSON file for loading V-Ray
{
    "env": [
        { "INSTALL_ROOT" : "C:\Program Files\Chaos Group\V-Ray\Houdini 18.0.532" },
 
        { "VRAY_APPSDK"     : "${INSTALL_ROOT}/appsdk" },
        { "VRAY_OSL_PATH"   : "${INSTALL_ROOT}/appsdk/bin" },
        { "VRAY_UI_DS_PATH" : "${INSTALL_ROOT}/ui" },
        { "VFH_HOME"        : "${INSTALL_ROOT}/vfh_home" },
 
        { "PYTHONPATH" : "${INSTALL_ROOT}/appsdk/python27" },
 
        { "PATH" : [
            "${HFS}/bin;${VRAY_APPSDK}/bin",
            "${VFH_HOME}/bin"
        ] },
 
        { "HOUDINI13_VOLUME_COMPATIBILITY" : 1 },
        { "HDF5_DISABLE_VERSION_CHECK"     : 1 }
    ],
    "path" : [
        "${VFH_HOME}"
    ]
}
 

Windows
To deploy V-Ray using the ZIP archive instead of the installer:

Unzip the V-Ray for Houdini archive
Move it to a location of your choice (e.g. "D:/V-Ray")
Place the "vray_for_houdini.json" file under "$HFS/packages"
Edit the "vray_for_houdini.json" and set the "INSTALL_ROOT" variable to point to the location of the V-Ray files (e.g. "INSTALL_ROOT" : "D:/V-Ray")
Start Houdini
Linux and Mac OS
In Linux or Mac envronment, the process is exactly the same.

 

For detailed information on how to run V-Ray for Houdini, see the QuickStart Guides Introduction tutorial. 

