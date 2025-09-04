#!/usr/bin/env python3
"""
Test loading RenderMan shared libraries in Houdini
"""

import os
import sys
import glob
import ctypes
from ctypes import cdll
import subprocess

def find_shared_libraries():
    """Find all shared libraries in RenderMan directories"""
    print("=== Finding RenderMan Shared Libraries ===")
    
    # Paths to search
    search_paths = [
        "/opt/pixar/RenderManProServer-26.3",
        "/opt/pixar/RenderManForHoudini-26.3"
    ]
    
    libraries = []
    
    for base_path in search_paths:
        if os.path.exists(base_path):
            print(f"\nSearching in: {base_path}")
            
            # Find .so files
            so_files = []
            for root, dirs, files in os.walk(base_path):
                for file in files:
                    if file.endswith('.so') or '.so.' in file:
                        full_path = os.path.join(root, file)
                        so_files.append(full_path)
            
            print(f"Found {len(so_files)} shared libraries")
            for lib in sorted(so_files):
                rel_path = lib.replace(base_path, "")
                print(f"  {rel_path}")
                libraries.append(lib)
        else:
            print(f"Path not found: {base_path}")
    
    return libraries

def test_library_loading(libraries):
    """Test loading libraries with ctypes"""
    print("\n=== Testing Library Loading with ctypes ===")
    
    results = {
        'success': [],
        'failed': [],
        'errors': {}
    }
    
    for lib_path in libraries:
        lib_name = os.path.basename(lib_path)
        try:
            print(f"\nTesting: {lib_name}")
            
            # Try to load with ctypes
            lib = cdll.LoadLibrary(lib_path)
            print(f"  ✅ SUCCESS: Loaded {lib_name}")
            results['success'].append(lib_path)
            
        except Exception as e:
            print(f"  ❌ FAILED: {lib_name} - {str(e)}")
            results['failed'].append(lib_path)
            results['errors'][lib_path] = str(e)
    
    return results

def test_with_ldd(libraries):
    """Test library dependencies with ldd"""
    print("\n=== Testing Library Dependencies with ldd ===")
    
    dependency_issues = {}
    
    for lib_path in libraries[:10]:  # Test first 10 to avoid too much output
        lib_name = os.path.basename(lib_path)
        try:
            print(f"\nChecking dependencies for: {lib_name}")
            
            result = subprocess.run(['ldd', lib_path], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                output = result.stdout
                missing_deps = []
                
                for line in output.split('\n'):
                    if 'not found' in line:
                        missing_deps.append(line.strip())
                
                if missing_deps:
                    print(f"  ❌ Missing dependencies:")
                    for dep in missing_deps:
                        print(f"    {dep}")
                    dependency_issues[lib_path] = missing_deps
                else:
                    print(f"  ✅ All dependencies found")
            else:
                print(f"  ⚠️  ldd failed: {result.stderr}")
                
        except subprocess.TimeoutExpired:
            print(f"  ⚠️  ldd timeout for {lib_name}")
        except Exception as e:
            print(f"  ⚠️  Error checking {lib_name}: {e}")
    
    return dependency_issues

def test_houdini_loading():
    """Test loading RenderMan in Houdini context"""
    print("\n=== Testing RenderMan Loading in Houdini Context ===")
    
    try:
        import hou
        print("✅ Houdini module imported successfully")
        
        # Try to access RenderMan nodes
        try:
            # Check if RenderMan node types are available
            node_types = hou.nodeTypeCategories()
            rop_category = node_types.get('Driver')
            
            if rop_category:
                renderman_nodes = []
                for node_type in rop_category.nodeTypes().values():
                    if 'renderman' in node_type.name().lower() or 'prman' in node_type.name().lower():
                        renderman_nodes.append(node_type.name())
                
                if renderman_nodes:
                    print(f"✅ Found RenderMan node types: {renderman_nodes}")
                else:
                    print("❌ No RenderMan node types found")
            
        except Exception as e:
            print(f"❌ Error checking RenderMan nodes: {e}")
            
        # Try to create a RenderMan ROP
        try:
            rop_net = hou.node('/out')
            if not rop_net:
                rop_net = hou.node('/').createNode('ropnet', 'out')
            
            # Try to create RenderMan ROP
            rman_rop = rop_net.createNode('ris', 'test_renderman')
            print("✅ Successfully created RenderMan ROP node")
            
            # Clean up
            rman_rop.destroy()
            
        except Exception as e:
            print(f"❌ Failed to create RenderMan ROP: {e}")
            
    except ImportError as e:
        print(f"❌ Failed to import Houdini module: {e}")
        return False
    
    return True

def main():
    print("RenderMan Shared Library Test")
    print("=" * 50)
    
    # Find all shared libraries
    libraries = find_shared_libraries()
    
    if not libraries:
        print("No shared libraries found!")
        return
    
    print(f"\nTotal libraries found: {len(libraries)}")
    
    # Test loading with ctypes
    load_results = test_library_loading(libraries)
    
    # Test dependencies with ldd
    dep_issues = test_with_ldd(libraries)
    
    # Test in Houdini context
    houdini_success = test_houdini_loading()
    
    # Summary
    print("\n" + "=" * 50)
    print("SUMMARY")
    print("=" * 50)
    
    print(f"Libraries found: {len(libraries)}")
    print(f"Successfully loaded: {len(load_results['success'])}")
    print(f"Failed to load: {len(load_results['failed'])}")
    print(f"Libraries with missing dependencies: {len(dep_issues)}")
    print(f"Houdini integration: {'✅ Working' if houdini_success else '❌ Issues'}")
    
    if load_results['failed']:
        print(f"\nFailed libraries:")
        for lib in load_results['failed']:
            lib_name = os.path.basename(lib)
            error = load_results['errors'].get(lib, 'Unknown error')
            print(f"  {lib_name}: {error}")
    
    if dep_issues:
        print(f"\nLibraries with dependency issues:")
        for lib, deps in dep_issues.items():
            lib_name = os.path.basename(lib)
            print(f"  {lib_name}: {len(deps)} missing dependencies")

if __name__ == "__main__":
    main()