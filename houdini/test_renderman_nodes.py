#!/usr/bin/env python3
"""
Test script to check if RenderMan nodes are available in Houdini
"""
import hou
import os

print("=" * 60)
print("RENDERMAN INTEGRATION TEST")
print("=" * 60)

# Clear any existing scene
hou.hipFile.clear()

# Check environment variables
print("\nEnvironment Variables:")
print(f"HOUDINI_PATH: {os.environ.get('HOUDINI_PATH', 'Not set')}")
print(f"RMANTREE: {os.environ.get('RMANTREE', 'Not set')}")
print(f"RFHTREE: {os.environ.get('RFHTREE', 'Not set')}")

# Get all node categories
all_categories = hou.nodeTypeCategories()
print(f"\nAvailable node categories: {list(all_categories.keys())}")

# Check for RenderMan nodes in VOP category
print("\n" + "-" * 40)
print("CHECKING VOP NODES")
print("-" * 40)
vop_cat = all_categories.get('Vop')
if vop_cat:
    vop_types = vop_cat.nodeTypes()
    rman_vop_nodes = [name for name in vop_types.keys() if 'rman' in name.lower() or 'renderman' in name.lower()]
    
    if rman_vop_nodes:
        print(f"Found {len(rman_vop_nodes)} RenderMan VOP nodes:")
        for node in sorted(rman_vop_nodes):
            print(f"  - {node}")
    else:
        print("No RenderMan VOP nodes found")
        # Show first 10 VOP nodes for reference
        print("Available VOP nodes (first 10):")
        for i, node in enumerate(sorted(vop_types.keys())[:10]):
            print(f"  - {node}")
else:
    print("VOP category not found")

# Check for RenderMan nodes in ROP/Driver category
print("\n" + "-" * 40)
print("CHECKING ROP/DRIVER NODES")
print("-" * 40)
rop_cat = all_categories.get('Driver')
if rop_cat:
    rop_types = rop_cat.nodeTypes()
    rman_rop_nodes = [name for name in rop_types.keys() if 'rman' in name.lower() or 'renderman' in name.lower() or 'prman' in name.lower()]
    
    if rman_rop_nodes:
        print(f"Found {len(rman_rop_nodes)} RenderMan ROP nodes:")
        for node in sorted(rman_rop_nodes):
            print(f"  - {node}")
    else:
        print("No RenderMan ROP nodes found")
        # Show all ROP nodes for reference
        print("Available ROP nodes:")
        for node in sorted(rop_types.keys()):
            print(f"  - {node}")
else:
    print("Driver category not found")

# Check for RenderMan nodes in SOP category
print("\n" + "-" * 40)
print("CHECKING SOP NODES")
print("-" * 40)
sop_cat = all_categories.get('Sop')
if sop_cat:
    sop_types = sop_cat.nodeTypes()
    rman_sop_nodes = [name for name in sop_types.keys() if 'rman' in name.lower() or 'renderman' in name.lower()]
    
    if rman_sop_nodes:
        print(f"Found {len(rman_sop_nodes)} RenderMan SOP nodes:")
        for node in sorted(rman_sop_nodes):
            print(f"  - {node}")
    else:
        print("No RenderMan SOP nodes found")

print("\n" + "=" * 60)
print("TEST COMPLETE")
print("=" * 60)