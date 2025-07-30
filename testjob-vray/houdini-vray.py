import hou
import os

# Create a new Houdini scene
hou.hipFile.clear()

# List all available output nodes to check what's available
print("Available Output/ROP nodes:")
for name, node_type in sorted(hou.nodeTypeCategories()['Driver'].nodeTypes().items()):
    print(f"  {name}: {node_type.description()}")
print("")

# Create a simple geometry
geo = hou.node("/obj").createNode("geo", "simple_geo")
box = geo.createNode("box", "simple_box")

# Create a color node to add red color to the box
color = geo.createNode("color", "red_color")
color.setInput(0, box)
color.parm("colorr").set(1.0)  # Red
color.parm("colorg").set(0.0)  # No green
color.parm("colorb").set(0.0)  # No blue

# Create a camera
cam = hou.node("/obj").createNode("cam", "render_cam")
# Position the camera to view the box
cam.parmTuple("t").set((5, 5, 5))  # Position
cam.parmTuple("r").set((-30, 45, 0))  # Rotation

# Create a V-Ray renderer (VRay works in IPR mode by default)
print("Creating VRay renderer node...")
vray = hou.node("/out").createNode("vray", "vray_renderer")
print("VRay node created successfully")

# Check VRay node parameters for IPR-related settings
print("\nVRay node parameters (looking for IPR-related):")
vray_parms = [p.name() for p in vray.parms()]
ipr_parms = [p for p in vray_parms if 'ipr' in p.lower()]
if ipr_parms:
    print("IPR-related parameters found:")
    for parm in ipr_parms:
        print(f"  {parm}")
else:
    print("No IPR-specific parameters found")

print(f"\nAll VRay parameters (first 50):")
for i, parm_name in enumerate(vray_parms[:50]):
    print(f"  {i+1}. {parm_name}")

if len(vray_parms) > 50:
    print(f"  ... and {len(vray_parms) - 50} more parameters")
print("")

# Inspect IPR parameters before configuring
print("Inspecting IPR parameters...")
try:
    if vray.parm("vray_ipr_main"):
        parm = vray.parm("vray_ipr_main")
        print(f"vray_ipr_main:")
        print(f"  Current value: {parm.eval()}")
        print(f"  Parameter type: {parm.parmTemplate().type()}")
        print(f"  Description: {parm.description()}")
        if hasattr(parm.parmTemplate(), 'menuItems'):
            menu_items = parm.parmTemplate().menuItems()
            menu_labels = parm.parmTemplate().menuLabels()
            if menu_items:
                print(f"  Menu options:")
                for item, label in zip(menu_items, menu_labels):
                    print(f"    {item}: {label}")
    
    if vray.parm("soho_ipr_support"):
        parm = vray.parm("soho_ipr_support")
        print(f"soho_ipr_support:")
        print(f"  Current value: {parm.eval()}")
        print(f"  Parameter type: {parm.parmTemplate().type()}")
        print(f"  Description: {parm.description()}")
        if hasattr(parm.parmTemplate(), 'menuItems'):
            menu_items = parm.parmTemplate().menuItems()
            menu_labels = parm.parmTemplate().menuLabels()
            if menu_items:
                print(f"  Menu options:")
                for item, label in zip(menu_items, menu_labels):
                    print(f"    {item}: {label}")
        
except Exception as e:
    print(f"Error inspecting IPR parameters: {e}")

# Configure VRay for IPR mode based on inspection
print("\nConfiguring VRay for IPR mode...")
try:
    if vray.parm("vray_ipr_main"):
        # Set to 1 if it's a toggle, or check menu options
        vray.parm("vray_ipr_main").set(1)
        print(f"Set vray_ipr_main to: {vray.parm('vray_ipr_main').eval()}")
    
    if vray.parm("soho_ipr_support"):
        vray.parm("soho_ipr_support").set(1)
        print(f"Set soho_ipr_support to: {vray.parm('soho_ipr_support').eval()}")
        
except Exception as e:
    print(f"Warning: Could not configure IPR parameters: {e}")

# Configure VRay renderer - set output file
try:
    if vray.parm("soho_diskfile"):
        vray.parm("soho_diskfile").set("/work/vray_output.png")
        print("Set output file using soho_diskfile")
    elif vray.parm("picture"):
        vray.parm("picture").set("/work/vray_output.png")
        print("Set output file using picture")
except Exception as e:
    print(f"Warning: Could not set output file parameter: {e}")

# Set camera
try:
    if vray.parm("SettingsCamera_camera"):
        vray.parm("SettingsCamera_camera").set("/obj/render_cam")
        print("Set camera using SettingsCamera_camera")
    elif vray.parm("camera"):
        vray.parm("camera").set("/obj/render_cam")
        print("Set camera using camera")
except Exception as e:
    print(f"Warning: Could not set camera parameter: {e}")

# Set frame range parameters
try:
    if vray.parm("trange"):
        vray.parm("trange").set(1)  # Set to render frame range
        print("Set trange parameter")
    if vray.parm("f1"):
        vray.parm("f1").set(1)      # Start frame
        print("Set f1 parameter")
    if vray.parm("f2"):
        vray.parm("f2").set(1)      # End frame
        print("Set f2 parameter")
    if vray.parm("f3"):
        vray.parm("f3").set(1)      # Frame increment
        print("Set f3 parameter")
except Exception as e:
    print(f"Warning: Could not set frame range parameters: {e}")

# Save the scene
hou.hipFile.save("/work/simple_scene_vray.hip")

print("Created a simple scene with a V-Ray renderer at /out/vray_renderer")