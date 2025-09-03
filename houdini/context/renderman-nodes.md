# RenderMan Output Nodes in Houdini 20.5.445

## RenderMan-Specific Output Nodes

The following RenderMan output nodes are available in this Houdini installation with RenderMan for Houdini 26.3:

- **`ris::3.0`** - RenderMan (Main RIS renderer)
- **`hdprman::3.0`** - RenderMan Hydra (Hydra-based RenderMan renderer)
- **`denoise::3.0`** - RenderMan Denoise

## All Available Output Node Types

Complete list of output node types available in Houdini 20.5.445:

- `batch` - Batch
- `channel` - Channel
- `chopnet` - CHOP Network
- `comp` - Composite
- `cop2net` - COP Network - Old
- `copnet` - COP Network
- `denoise::3.0` - RenderMan Denoise
- `dop` - Dynamics
- `dopnet` - DOP Network
- `fetch` - Fetch
- `framecontainer` - Frame Container
- `framedep` - Frame Dependency
- `geometry` - Geometry
- `geometryraw` - Geometry Raw
- `hdprman::3.0` - RenderMan Hydra
- `image` - Image
- `image3d` - 3D Texture Generator
- `lopnet` - LOP Network
- `matnet` - Material Network
- `mdd` - MDD Point Cache
- `merge` - Merge
- `netbarrier` - Net Barrier
- `objnet` - Object Network
- `prepost` - PrePost
- `ris::3.0` - RenderMan
- `shell` - Shell
- `shopnet` - SHOP Network
- `sopnet` - SOP Network
- `subnet` - Subnetwork
- `switch` - Switch
- `topnet` - TOP Network
- `usd` - USD
- `usdrender` - USD Render
- `vopnet` - VOP Network

## Usage Notes

- Use `ris::3.0` for traditional RenderMan RIS rendering
- Use `hdprman::3.0` for Hydra-based RenderMan rendering (newer approach)
- Both nodes should work with RenderMan ProServer 26.3
- The `denoise::3.0` node can be used for post-render denoising

## Environment

- **Houdini Version**: 20.5.445
- **RenderMan for Houdini**: 26.3 (build 2352169)
- **RenderMan ProServer**: 26.3 (build 2352291)
- **Platform**: RHEL9/gcc11