# Rocky Linux 9 + Amazon DCV GPU Desktop Container

GPU-accelerated remote desktop container using Amazon DCV 2025.0 on Rocky Linux 9 with MATE desktop, VirtualGL, and Blender 5.0.

## Architecture

This setup has two layers:

1. **Host EC2 instance**: runs the NVIDIA driver, Docker, and NVIDIA Container Toolkit
2. **Container**: runs DCV server, MATE desktop, VirtualGL, and Blender inside a CUDA runtime base image

The GPU driver lives on the host and is passed into the container via the NVIDIA Container Toolkit runtime. The container does NOT install any GPU drivers — it only needs the CUDA runtime libraries (provided by the `nvidia/cuda` base image).

GPU-accelerated OpenGL is provided by VirtualGL, which routes GL calls from apps to the NVIDIA GPU via `/dev/dri`. The desktop itself (MATE) runs on software rendering, while individual apps (like Blender) get GPU acceleration when launched with `vglrun`.

## Dockerfiles

| File | Desktop | GPU GL | DCV Version | Status |
|------|---------|--------|-------------|--------|
| `Dockerfile.rocky-nice-dcv-gnome` | MATE + VirtualGL | GPU (vglrun) | 2025.0 | Working |
| `Dockerfile.rocky-nice-dcv` | XFCE | Software (gl off) | 2025.0 | Working |
| `Dockerfile.rocky` | XFCE + VNC/noVNC | N/A | N/A | Working (no DCV) |

## Host Setup

The host EC2 instance must have the NVIDIA driver, Docker, and NVIDIA Container Toolkit installed.

Reference: [Install NVIDIA GPU driver, CUDA Toolkit, NVIDIA Container Toolkit on RHEL/Rocky Linux 8/9/10](https://repost.aws/articles/ARpmJcNiCtST2A3hrrM_4R4A/install-nvidia-gpu-driver-cuda-toolkit-nvidia-container-toolkit-on-amazon-ec2-instances-running-rhel-rocky-linux-8-9-10)

### Quick host setup (Rocky Linux 9)

```bash
sudo dnf update -y
sudo dnf config-manager --set-enabled crb
sudo dnf install -y epel-release dkms kernel-devel kernel-modules-extra gcc make \
    vulkan-devel libglvnd-devel elfutils-libelf-devel

# NVIDIA driver
sudo dnf config-manager --add-repo \
    http://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
sudo dnf module enable -y nvidia-driver:open-dkms
sudo dnf install -y nvidia-open

# Docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker

# NVIDIA Container Toolkit
sudo dnf config-manager --add-repo \
    https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
sudo dnf install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

## Build & Run (MATE + VirtualGL — recommended)

```bash
cd docker
docker build -f Dockerfile.rocky-nice-dcv-gnome -t rocky-dcv-vgl .

docker run --runtime=nvidia --gpus all \
    --network host \
    --cap-add SYS_PTRACE \
    --device /dev/dri:/dev/dri \
    rocky-dcv-vgl
```

Connect at `https://<host-ip>:8443` — credentials: `rockyuser` / `rocky`

### Docker run flags explained

- `--runtime=nvidia --gpus all` — pass GPU to container
- `--network host` — DCV binds port 8443 directly on host
- `--cap-add SYS_PTRACE` — required for DCV agent to inspect processes
- `--device /dev/dri:/dev/dri` — required for VirtualGL GPU access

### DCV License (EC2)

DCV is free on EC2 but the instance IAM role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::dcv-license.<region>/*"
    }
  ]
}
```

### SSM Port Forward

```bash
aws ssm start-session \
    --target <instance-id> \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["8443"],"localPortNumber":["8443"]}' \
    --region <region>
```

## Verify GPU Acceleration

From a terminal inside the DCV session:

```bash
vglrun glxinfo | grep "OpenGL renderer"
# Expected: OpenGL renderer string: NVIDIA L40S/PCIe/SSE2 (or your GPU)
```

If it says `llvmpipe`, VirtualGL isn't routing to the GPU.

Blender launched from the desktop shortcut already uses `vglrun`. For other apps:

```bash
vglrun <application>
```

## What's Inside

| Component | Details |
|-----------|---------|
| Base image | `nvidia/cuda:12.4.0-runtime-rockylinux9` |
| Desktop | MATE (lightweight, no systemd required) |
| GPU OpenGL | VirtualGL 3.1 (`vglrun` per-app) |
| Remote display | Amazon DCV 2025.0 (port 8443, HTTPS) |
| Application | Blender 5.0.1 with sample scene on desktop |
| GPU passthrough | NVIDIA Container Toolkit + `/dev/dri` |

## DCV vs VNC

| | DCV (this) | VNC (Dockerfile.rocky) |
|---|---|---|
| Protocol | DCV (H.264/QUIC) | RFB + WebSocket |
| GPU encoding | Yes (NVENC) | No |
| Port | 8443 (HTTPS) | 5901 / 6080 |
| Client | Browser or native DCV client | Browser (noVNC) |
| GPU OpenGL | Yes (via VirtualGL) | No |

## Files

- `Dockerfile.rocky-nice-dcv-gnome` — MATE + VirtualGL + DCV 2025.0 (recommended)
- `start-dcv-gnome.sh` — entrypoint for MATE container
- `Dockerfile.rocky-nice-dcv` — XFCE + DCV 2025.0 (no GPU GL, simpler)
- `start-dcv.sh` — entrypoint for XFCE container
- `Dockerfile.rocky` — XFCE + VNC/noVNC (no DCV)
- `design/dcv-desktop-options.md` — evaluation of desktop environments tested

## Troubleshooting & Debugging

### Issue 1: "Could not create session — Could not get the system bus"

DCV requires D-Bus. Fix: start `dbus-daemon --system` before DCV in the entrypoint.

### Issue 2: Browser shows ERR_EMPTY_RESPONSE

Missing `nice-dcv-web-viewer` package. Add it to the RPM install list.

### Issue 3: "No license available"

EC2 IAM role needs `s3:GetObject` on `arn:aws:s3:::dcv-license.<region>/*`.

### Issue 4: Login succeeds but spinner / no desktop

Multiple causes found during development:

- DCV 2024.0 DCV-GL crashes GTK3 desktops (XFCE, MATE) via LD_PRELOAD — upgrade to 2025.0
- GNOME requires systemd/logind — doesn't work in containers without `--privileged`
- Console sessions with Xvfb don't render — use virtual sessions instead
- DCV-GL can't find GL vendor on Xdcv display — use VirtualGL instead

### Issue 5: "The dcvserver service is not running"

`dcv create-session` ran before server was ready. Poll with `dcv list-sessions` in a loop.

### Issue 6: "Address already in use" on port 8443

Previous container still holding the port. Stop and remove it first.

### Issue 7: Agent "Permission denied" on /proc

Add `--cap-add SYS_PTRACE` to docker run.

### Issue 8: VirtualGL "Invalid EGL device"

Don't wrap the entire desktop session with `vglrun`. Only wrap individual GPU apps. The desktop runs on software rendering, apps get GPU via `vglrun`.

### Useful debug commands

```bash
# DCV server logs
docker exec <container> cat /var/log/dcv/server.log

# Session launcher logs
docker exec <container> cat /var/log/dcv/dcv-xsession.rockyuser.rockyuser-session.log

# License status
docker exec <container> grep -i licen /var/log/dcv/server.log

# List sessions
docker exec <container> dcv list-sessions

# Check GL renderer
docker exec <container> su - rockyuser -c "DISPLAY=:0 XAUTHORITY=... vglrun glxinfo | grep renderer"

# Check processes
docker exec <container> ps aux | grep -E "mate|marco|caja|dcv"
```

## References

- [Amazon DCV documentation](https://docs.aws.amazon.com/dcv/)
- [Amazon DCV downloads](https://www.amazondcv.com/)
- [Host GPU setup (RHEL/Rocky)](https://repost.aws/articles/ARpmJcNiCtST2A3hrrM_4R4A/install-nvidia-gpu-driver-cuda-toolkit-nvidia-container-toolkit-on-amazon-ec2-instances-running-rhel-rocky-linux-8-9-10)
- [VirtualGL](https://github.com/VirtualGL/virtualgl)
- [ni-sp.com: DCV desktop environments](https://www.ni-sp.com/knowledge-base/dcv-general/kde-gnome-mate-and-others/)
- [ni-sp.com: DCV in containers](https://www.ni-sp.com/knowledge-base/dcv-installation/linux-containers/)
- [AWS: DCV failsafe virtual session](https://docs.aws.amazon.com/dcv/latest/adminguide/creating-linux-failsafe-virtual-session-creation.html)
