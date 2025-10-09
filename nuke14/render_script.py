#!/usr/bin/env python

import nuke
import sys
import os

# Load the motion blur Nuke script
nuke.scriptOpen('/samples/motionblur2d_10.nk')

# Check if Write1 node exists, if not create one
write_node = nuke.toNode('Write1')
if not write_node:
    print("Write1 node not found, creating one...")
    # Get the last node in the script (usually the output)
    last_node = None
    for node in nuke.allNodes():
        if node.Class() in ['Viewer', 'VectorBlur2', 'MotionBlur2D']:
            last_node = node
    
    if last_node:
        # Create a Write node
        write_node = nuke.nodes.Write()
        write_node.setInput(0, last_node)
        write_node.setName('Write1')
        print(f"Created Write1 node connected to {last_node.name()}")
    else:
        print("No suitable node found to connect Write node!")
        sys.exit(1)

# Set the output path for the Write node
write_node['file'].setValue('/tmp/output/simple.%04d.png')
print("Set output path to: /tmp/output/simple.%04d.png (motion blur render)")

# Execute the render for 120 frames
try:
    nuke.execute(write_node, 1, 120)
    print("Render completed successfully!")
except Exception as e:
    print(f"Render failed: {e}")
    sys.exit(1)