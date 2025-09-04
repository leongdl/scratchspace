#!/usr/bin/env python3
"""
Create a simple RIB file and test prman directly
"""

import sys
import os
import subprocess

def create_simple_rib(output_dir="/workspace/output"):
    """
    Create a simple RIB file manually
    """
    try:
        os.makedirs(output_dir, exist_ok=True)
        
        rib_file = os.path.join(output_dir, "simple_test.rib")
        output_file = os.path.join(output_dir, "simple_test.exr")
        
        # Create a very basic RIB file
        rib_content = f'''##RenderMan RIB
version 3.04
Option "searchpath" "shader" ["/opt/pixar/RenderManProServer-26.3/lib/shaders"]
Display "{output_file}" "openexr" "rgba"
Format 320 240 1
Projection "perspective" "fov" [45]
WorldBegin
    LightSource "PxrDomeLight" 1 "string lightColorMap" [""]
    AttributeBegin
        Color [1 0 0]
        Translate 0 0 0
        Sphere 1 -1 1 360
    AttributeEnd
WorldEnd
'''
        
        with open(rib_file, 'w') as f:
            f.write(rib_content)
        
        print(f"Created simple RIB file: {rib_file}")
        print(f"Expected output: {output_file}")
        
        return rib_file, output_file
        
    except Exception as e:
        print(f"Error creating RIB file: {str(e)}")
        return None, None

def test_prman_render(rib_file, output_file):
    """
    Test prman rendering directly
    """
    try:
        if not os.path.exists(rib_file):
            print(f"RIB file not found: {rib_file}")
            return False
        
        print(f"Testing prman render...")
        print(f"RIB file: {rib_file}")
        
        # Show RIB content
        with open(rib_file, 'r') as f:
            print(f"RIB content:\n{f.read()}")
        
        # Test different prman variants
        variants = [None, 'xpucpu', 'xpu']  # None = default CPU renderer
        
        for variant in variants:
            print(f"\n--- Testing prman with variant: {variant or 'default'} ---")
            
            if variant:
                cmd = ['prman', '-variant', variant, '-progress', rib_file]
            else:
                cmd = ['prman', '-progress', rib_file]
            print(f"Running: {' '.join(cmd)}")
            
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                
                print(f"Return code: {result.returncode}")
                if result.stdout:
                    print(f"stdout:\n{result.stdout}")
                if result.stderr:
                    print(f"stderr:\n{result.stderr}")
                
                # Check if output was created
                if os.path.exists(output_file):
                    file_size = os.path.getsize(output_file)
                    print(f"✅ Success with {variant}! Output: {output_file} ({file_size} bytes)")
                    return True
                else:
                    print(f"❌ No output file created with {variant}")
                    
            except subprocess.TimeoutExpired:
                print(f"❌ Timeout with variant {variant}")
            except Exception as e:
                print(f"❌ Error with variant {variant}: {str(e)}")
        
        return False
        
    except Exception as e:
        print(f"Error testing prman: {str(e)}")
        return False

def main():
    output_dir = sys.argv[1] if len(sys.argv) > 1 else "/workspace/output"
    
    print("Testing prman directly with simple RIB file")
    print(f"Output directory: {output_dir}")
    
    # Check prman availability
    try:
        result = subprocess.run(['prman', '-version'], capture_output=True, text=True)
        print(f"prman version:\n{result.stdout}")
    except Exception as e:
        print(f"prman not available: {str(e)}")
        sys.exit(1)
    
    # Create simple RIB
    rib_file, output_file = create_simple_rib(output_dir)
    if not rib_file:
        print("Failed to create RIB file")
        sys.exit(1)
    
    # Test prman
    success = test_prman_render(rib_file, output_file)
    
    if success:
        print(f"\n🎉 prman direct render successful!")
        sys.exit(0)
    else:
        print(f"\n❌ prman direct render failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()