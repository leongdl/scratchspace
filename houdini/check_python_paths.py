#!/usr/bin/env python3

import sys
import os

def check_python_paths():
    """Check Python paths and Houdini module availability"""
    
    print("Python Path Analysis")
    print("=" * 50)
    
    print("Python executable:", sys.executable)
    print("Python version:", sys.version)
    print()
    
    print("Python sys.path:")
    print("-" * 30)
    for i, path in enumerate(sys.path):
        print(f"  {i+1:2d}. {path}")
    print()
    
    # Check Houdini environment variables
    print("Houdini Environment Variables:")
    print("-" * 30)
    houdini_vars = ['HFS', 'HOUDINI_PATH', 'PYTHONPATH', 'LD_LIBRARY_PATH']
    for var in houdini_vars:
        value = os.environ.get(var, 'NOT SET')
        print(f"  {var}: {value}")
    print()
    
    # Check for houdinihelp specifically
    print("Searching for houdinihelp module:")
    print("-" * 30)
    
    # Look in common Houdini Python locations
    hfs = os.environ.get('HFS', '/opt/houdini')
    potential_paths = [
        f"{hfs}/python/lib/python3.10/site-packages",
        f"{hfs}/python/lib/python3.9/site-packages", 
        f"{hfs}/python/lib/site-packages",
        f"{hfs}/houdini/python3.10libs",
        f"{hfs}/houdini/python3.9libs",
        f"{hfs}/houdini/python2.7libs",
        f"{hfs}/python",
        f"{hfs}/bin"
    ]
    
    for path in potential_paths:
        if os.path.exists(path):
            print(f"✅ Found: {path}")
            # Check contents
            try:
                contents = os.listdir(path)
                houdini_modules = [f for f in contents if 'houdini' in f.lower()]
                if houdini_modules:
                    print(f"    Houdini modules: {houdini_modules}")
            except:
                pass
        else:
            print(f"❌ Missing: {path}")
    
    print()
    
    # Try to find houdinihelp files
    print("Searching for houdinihelp files:")
    print("-" * 30)
    
    import subprocess
    try:
        result = subprocess.run(['find', hfs, '-name', '*houdinihelp*', '-type', 'f'], 
                              capture_output=True, text=True, timeout=10)
        if result.stdout.strip():
            print("Found houdinihelp files:")
            for line in result.stdout.strip().split('\n'):
                print(f"  {line}")
        else:
            print("❌ No houdinihelp files found")
    except Exception as e:
        print(f"Search failed: {e}")
    
    print()
    
    # Check if we can import hou
    print("Testing Houdini module imports:")
    print("-" * 30)
    
    try:
        import hou
        print("✅ hou module imported successfully")
        print(f"   hou.__file__: {hou.__file__}")
    except Exception as e:
        print(f"❌ hou import failed: {e}")
    
    try:
        import houdinihelp
        print("✅ houdinihelp module imported successfully")
    except Exception as e:
        print(f"❌ houdinihelp import failed: {e}")

if __name__ == "__main__":
    check_python_paths()