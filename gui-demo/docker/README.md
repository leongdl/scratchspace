# Docker — GPU-Accelerated Rocky Linux VNC Desktop

Rocky Linux 9 container with XFCE desktop, TigerVNC, and noVNC for browser-based access. Based on `nvidia/cuda:12.4.0-runtime-rockylinux9` so GPU workloads work out of the box.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile.rocky` | Container image definition |
| `start.sh` | Entrypoint — starts VNC server + websockify |

## Build

```bash
docker build -t rocky-vnc:latest -f Dockerfile.rocky .
```

## Run Locally

```bash
docker run -d --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  --network host \
  --name rocky-vnc \
  rocky-vnc:latest
```

Open http://localhost:6080/vnc.html — password: `password`

## Push to ECR

```bash
REGISTRY=224071664257.dkr.ecr.us-west-2.amazonaws.com
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $REGISTRY
docker tag rocky-vnc:latest $REGISTRY/sqex2:rocky-vnc
docker push $REGISTRY/sqex2:rocky-vnc
```

## Headless Rendering

Render the sample scene from the command line without opening the GUI.

Cycles (ray-traced, physically accurate, slower):
```bash
/opt/blender/blender -b ~/Desktop/blender-4.3-splash.blend \
  -o ~/Desktop/render_#### -E CYCLES -f 1 -- --cycles-device CUDA
```

Eevee (rasterized, real-time engine, much faster):
```bash
xvfb-run -a /opt/blender/blender -b ~/Desktop/blender-4.3-splash.blend \
  -o ~/Desktop/render_#### -E BLENDER_EEVEE_NEXT -f 1
```

Eevee needs a GPU graphics context which doesn't exist in headless mode. `xvfb-run` provides a virtual framebuffer so Eevee can initialize OpenGL. Cycles uses CUDA compute directly and doesn't need this.

Output lands at `~/Desktop/render_0001.png`.

## Ports

| Port | Service |
|------|---------|
| 5901 | VNC server (internal) |
| 6080 | noVNC web interface |
