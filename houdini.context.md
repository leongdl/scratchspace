# Houdini Docker Container Context

## Stack Size Requirements

Houdini requires a larger stack size than the default Docker container provides. Without increasing the stack size, you'll see this warning:

```
WARNING: The maximum stack size allowed by the operating system (10485760 bytes)
         is significantly lower than the expected size. This may result in
         instability.
```

### Solution

When running the Houdini Docker container, you must increase the stack size using Docker's `--ulimit` flag:

```bash
docker run -it --rm --ulimit stack=52428800 houdini-vray:latest houdini --help
```

This sets the stack size to approximately 50MB (5 times the default 10MB), which resolves the warning.

### Convenience Script

A convenience script `run-houdini-vray.sh` has been provided that automatically includes the stack size parameter:

```bash
./run-houdini-vray.sh houdini --help
./run-houdini-vray.sh houdini-vray /render/houdini-karma.hip
```

### Batch Job Configuration

For batch jobs using template.yaml, the ulimit has been configured in the resource requirements section to ensure the stack size is set correctly at runtime.

## Licensing Notes

When running Houdini in a container, you may see licensing errors:

```
No licenses could be found to run this application.
Please check for a valid license server host
```

This is expected in a container environment without a license server. For production use, you'll need to configure a license server and make it accessible to the container.

## Houdini Rendering with hrender

The `hrender` command is a script that uses Houdini's Python interpreter (hython) to render scenes from the command line.

### Command Syntax

```
# Single frame rendering:
hrender [options] -d output_driver file.hip [imagefile]

# Frame range rendering:
hrender -e [options] -d output_driver file.hip
```

### Key Options

- `-d output_driver`: Specify the output driver node (e.g., `/out/mantra1`)
- `-c cop_path`: Specify a compositing output path (alternative to `-d`)
- `-w pixels`: Output width
- `-h pixels`: Output height
- `-F frame`: Render a specific frame number
- `-f start end`: Frame range (must be used with `-e`)
- `-i increment`: Frame increment for animation (must be used with `-e`)
- `-t take`: Render a specific take
- `-o output`: Output file path
- `-v`: Verbose mode
- `-b fraction`: Image processing fraction (0.01 to 1.0)

### What is the `-e` flag?

The `-e` flag is used to render a frame range rather than a single frame:
- Without `-e`, hrender renders a single frame
- With `-e`, you need to specify a frame range using `-f start end`

### How to Set the Output Path

Use the `-o` option to specify the output file path:
- Example: `-o /work/output.png` or `-o /work/output_$F.png` (where $F is replaced by the frame number)

### Example Commands

1. **Render a single frame with specified output:**
   ```bash
   hrender -d /out/mantra1 file.hip -o output.png
   ```

2. **Render a frame range with specified output:**
   ```bash
   hrender -e -f 1 10 -d /out/mantra1 file.hip -o output_$F.png
   ```

3. **Render with specific resolution:**
   ```bash
   hrender -w 1920 -h 1080 -d /out/mantra1 file.hip -o output.png
   ```

4. **Render with verbose output:**
   ```bash
   hrender -v -d /out/mantra1 file.hip -o output.png
   ```

5. **Render a specific take:**
   ```bash
   hrender -t main -d /out/mantra1 file.hip -o output.png
   ```

### Full Command in Docker

```bash
docker run --rm --ulimit stack=52428800 houdini-latest bash -c "cd /opt/houdini && source ./houdini_setup_bash && /opt/houdini/bin/hrender -d /out/mantra1 /path/to/file.hip -o /path/to/output.png -v"
```

## Renderer Detection and Output Parameters

### Mantra vs. Karma Renderers

Houdini supports multiple renderers, with Mantra being the traditional renderer and Karma being the newer renderer. These renderers use different parameter names for their output settings:

- **Mantra**: Uses `vm_picture` parameter for output path
- **Karma**: Uses `picture` parameter for output path

When using the `-o` option with `hrender`, the script attempts to set the output path using the appropriate parameter based on the renderer type. However, if the wrong renderer is specified, you may encounter errors like:

```
Traceback (most recent call last):
  File "/opt/houdini/bin/hrender.py", line 241, in <module>
    render(args)
  File "/opt/houdini/bin/hrender.py", line 220, in render
    set_overrides(args, rop_node)
  File "/opt/houdini/bin/hrender.py", line 183, in set_overrides
    rop_node.parm('vm_picture').set(args.o_option)
```

This error occurs when trying to set the Mantra-specific `vm_picture` parameter on a Karma node.

### Robust Renderer Detection

To handle both renderer types, you can use a Python script to detect the renderer type and set the appropriate parameter:

```python
import hou
hou.hipFile.load('/path/to/file.hip')
out_node = hou.node('/out/karma1') or hou.node('/out/mantra1')
if out_node:
    # Check if it's a Karma node or Mantra node and set the appropriate parameter
    param_name = 'picture' if 'karma' in out_node.type().name().lower() else 'vm_picture'
    out_node.parm(param_name).set('/path/to/output.png')
    hou.hipFile.save('/path/to/file.hip')
```

### Example Command with Renderer Detection

```bash
# First set the output path directly in the scene file
/opt/houdini/bin/hython -c "import hou; hou.hipFile.load('/work/scene.hip'); out_node = hou.node('/out/karma1') or hou.node('/out/mantra1'); if out_node: out_node.parm('picture' if 'karma' in out_node.type().name().lower() else 'vm_picture').set('/work/output.png'); hou.hipFile.save('/work/scene.hip')"

# Then render the scene
/opt/houdini/bin/hrender -d /out/karma1 /work/scene.hip -v || /opt/houdini/bin/hrender -d /out/mantra1 /work/scene.hip -v
```

This approach:
1. Detects whether the scene has a Karma or Mantra renderer node
2. Sets the output path using the appropriate parameter for the detected renderer
3. Saves the modified scene file
4. Attempts to render with the primary renderer, falling back to the alternative if needed
##
 Frame Range Parameters

When rendering with Houdini, you need to set frame range parameters to avoid the `'NoneType' object has no attribute 'parm'` error. This error often occurs when the renderer can't find the frame range settings.

### Setting Frame Range in Python

```python
# Create a Karma renderer
karma = hou.node('/out').createNode('karma', 'karma_renderer')
karma.parm('picture').set('/work/output.png')

# Set frame range parameters
karma.parm('trange').set(1)  # Set to render frame range (0=single frame, 1=frame range)
karma.parm('f1').set(1)      # Start frame
karma.parm('f2').set(1)      # End frame
karma.parm('f3').set(1)      # Frame increment
```

### Setting Frame Range with hrender

When using hrender, you can specify the frame range with the `-f` option:

```bash
# Render frames 1 to 10
/opt/houdini/bin/hrender -d /out/karma_renderer -f 1 10 /work/scene.hip -v

# Render a single frame (frame 1)
/opt/houdini/bin/hrender -d /out/karma_renderer -f 1 1 /work/scene.hip -v
```

### Common Frame Range Parameters

- `trange`: Time range type (0=single frame, 1=frame range, 2=custom range)
- `f1`: Start frame
- `f2`: End frame
- `f3`: Frame increment (step size)
- `f`: Frame expression (for custom ranges)