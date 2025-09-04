#!/usr/bin/env python3
"""
Simple test to load RenderMan shared libraries in hython
"""

import ctypes
import os

# List of RenderMan shared libraries for Houdini 20.0.896
libraries = [
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/display/d_rfh.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/dso/dynamicarray.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/dso/init.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/dso/materialbuilder.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/dso/pxrosl.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/dso/rfh_prefs_init.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/dso/uniformarray.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/lib/libpxrcore.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/lib/libstats.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/lib/rfh_batch.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/lib/rfh_ipr.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/lib/rfh_prefs.so",
    "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/openvdb/impl_openvdb.so"
]

print("Testing RenderMan Shared Library Loading")
print("=" * 50)

success_count = 0
fail_count = 0

for lib_path in libraries:
    lib_name = os.path.basename(lib_path)
    
    try:
        # Test if file exists
        if not os.path.exists(lib_path):
            print(f"❌ {lib_name}: File not found")
            fail_count += 1
            continue
            
        # Try to load with ctypes
        lib = ctypes.cdll.LoadLibrary(lib_path)
        print(f"✅ {lib_name}: Loaded successfully")
        success_count += 1
        
    except Exception as e:
        print(f"❌ {lib_name}: Failed - {str(e)}")
        fail_count += 1

print("\n" + "=" * 50)
print("SUMMARY")
print("=" * 50)
print(f"Total libraries tested: {len(libraries)}")
print(f"Successfully loaded: {success_count}")
print(f"Failed to load: {fail_count}")

if success_count > 0:
    print(f"\n✅ {success_count}/{len(libraries)} RenderMan libraries loaded successfully")
else:
    print(f"\n❌ No libraries could be loaded")