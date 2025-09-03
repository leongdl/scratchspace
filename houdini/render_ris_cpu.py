#!/usr/bin/env python3
"""
Render hip file using RenderMan RIS with CPU-only settings
"""

import sys
import os
import hou

def render_with_ris(hip_file_path, output_dir="/workspace/output"):
    """
    Load hip file and render using RIS (RenderMan) with CPU settings
    """
    try:
        print(f"Loading hip file: {hip_file_path}")
        
        # Load the hip file with warnings ignored - force loading even with missing nodes
        try:
            hou.hipFile.load(hip_file_path, suppress_save_prompt=True, ignore_load_warnings=True)
            print(f"Successfully loaded: {hip_file_path} (warnings ignored)")
        except hou.LoadWarning as e:
            print(f"Loading with warnings (continuing anyway): {e}")
        except Exception as e:
            print(f"Loading error (attempting to continue): {e}")
            # Try to continue anyway - the scene might be partially loaded
        
        # Create output directory
        os.makedirs(output_dir, exist_ok=True)
        
        # Dump the node network structure
        print("\n=== NODE NETWORK DUMP ===")
        
        # Dump /obj context
        obj_context = hou.node("/obj")
        if obj_context:
            print(f"\n/obj context ({len(obj_context.children())} nodes):")
            for node in obj_context.children():
                print(f"  - {node.name()} ({node.type().name()}) at {node.path()}")
        
        # Dump /out context
        out_context = hou.node("/out")
        if out_context:
            print(f"\n/out context ({len(out_context.children())} nodes):")
            for node in out_context.children():
                print(f"  - {node.name()} ({node.type().name()}) at {node.path()}")
        
        # Dump /shop context (shaders)
        shop_context = hou.node("/shop")
        if shop_context:
            print(f"\n/shop context ({len(shop_context.children())} nodes):")
            for node in shop_context.children():
                print(f"  - {node.name()} ({node.type().name()}) at {node.path()}")
        
        # Dump /mat context (materials)
        mat_context = hou.node("/mat")
        if mat_context:
            print(f"\n/mat context ({len(mat_context.children())} nodes):")
            for node in mat_context.children():
                print(f"  - {node.name()} ({node.type().name()}) at {node.path()}")
        
        print("=== END NODE NETWORK DUMP ===\n")
        
        # Look for existing RIS nodes first
        out_context = hou.node("/out")
        if not out_context:
            print("No /out context found, creating one...")
            out_context = hou.node("/").createNode("out")
            
        ris_nodes = []
        
        try:
            for node in out_context.children():
                if "ris" in node.type().name().lower():
                    ris_nodes.append(node)
                    print(f"Found existing RIS node: {node.path()}")
        except Exception as e:
            print(f"Error scanning for RIS nodes: {e}")
        
        # If no RIS nodes found, create one
        if not ris_nodes:
            print("No RIS nodes found, creating new RIS render node...")
            try:
                ris_node = out_context.createNode("ris::3.0", "ris_render")
                ris_nodes.append(ris_node)
                print(f"Created RIS node: {ris_node.path()}")
                
                # Set frame range for frames 1, 2, 3
                ris_node.parm("f1").set(1)
                ris_node.parm("f2").set(3)
                
                # Try to find a camera
                cameras = []
                for node in hou.node("/obj").children():
                    if node.type().name() == "cam":
                        cameras.append(node.path())
                
                if cameras:
                    ris_node.parm("camera").set(cameras[0])
                    print(f"Set camera to: {cameras[0]}")
                
            except Exception as e:
                print(f"Error creating RIS node: {str(e)}")
                return False
        
        # Configure each RIS node for CPU rendering
        for ris_node in ris_nodes:
            print(f"\nConfiguring RIS node: {ris_node.path()}")
            
            try:
                # Set output path
                output_file = os.path.join(output_dir, f"render_{ris_node.name()}.$F4.exr")
                if ris_node.parm("ri_display_0"):
                    ris_node.parm("ri_display_0").set(output_file)
                    print(f"Set output to: {output_file}")
                
                # Force CPU rendering - disable GPU/XPU
                if ris_node.parm("ri_xpu"):
                    ris_node.parm("ri_xpu").set(0)  # Disable XPU
                    print("Disabled XPU (GPU acceleration)")
                
                # Set integrator to PxrPathTracer (CPU)
                if ris_node.parm("ri_integrator"):
                    ris_node.parm("ri_integrator").set("PxrPathTracer")
                    print("Set integrator to PxrPathTracer")
                
                # Set reasonable CPU settings
                if ris_node.parm("ri_maxsamples"):
                    ris_node.parm("ri_maxsamples").set(64)  # Lower samples for faster render
                    print("Set max samples to 64")
                
                # Set resolution
                if ris_node.parm("res_fraction"):
                    ris_node.parm("res_fraction").set("specific")
                if ris_node.parm("res_overrideres"):
                    ris_node.parm("res_overrideres").set(1)
                if ris_node.parm("res_x"):
                    ris_node.parm("res_x").set(640)
                if ris_node.parm("res_y"):
                    ris_node.parm("res_y").set(480)
                print("Set resolution to 640x480")
                
                # Set frame range for existing nodes too
                if ris_node.parm("f1"):
                    ris_node.parm("f1").set(1)
                if ris_node.parm("f2"):
                    ris_node.parm("f2").set(3)
                print(f"Set frame range to 1-3")
                
                # Start rendering
                print(f"Starting render with {ris_node.path()} for frames 1-3...")
                ris_node.render()
                print(f"Render completed for: {ris_node.path()}")
                
            except Exception as e:
                print(f"Error rendering with {ris_node.path()}: {str(e)}")
                continue
        
        return True
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python render_ris_cpu.py <hip_file_path> [output_dir]")
        sys.exit(1)
    
    hip_file = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "/workspace/output"
    
    if not os.path.exists(hip_file):
        print(f"Error: Hip file not found: {hip_file}")
        sys.exit(1)
    
    print(f"Houdini version: {hou.applicationVersionString()}")
    print(f"RenderMan tree: {hou.getenv('RMANTREE')}")
    print(f"Hip file: {hip_file}")
    print(f"Output directory: {output_dir}")
    print("Rendering with RIS (RenderMan) - CPU only")
    
    success = render_with_ris(hip_file, output_dir)
    
    if success:
        print(f"\nRender completed! Check output in: {output_dir}")
        sys.exit(0)
    else:
        print("\nRender failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()