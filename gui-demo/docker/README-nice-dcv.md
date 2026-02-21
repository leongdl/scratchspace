# Rocky Linux 9 + NICE DCV GPU Desktop Container

GPU-accelerated remote desktop container using Amazon DCV (formerly NICE DCV) on Rocky Linux 9 with XFCE and Blender 5.0.

## Architecture

This setup has two layers:

1. **Host EC2 instance**: runs the NVIDIA driver, Docker, and NVIDIA Container Toolkit
2. **Container** (`Dockerfile.rocky-nice-dcv`): runs the DCV server, XFCE desktop, and Blender inside a CUDA runtime base image

The GPU driver lives on the host and is passed into the container via the NVIDIA Container Toolkit runtime. The container does NOT install any GPU drivers — it only needs the CUDA runtime libraries (provided by the `nvidia/cuda` base image).

This is different from the VNC-based `Dockerfile.rocky` which uses TigerVNC + noVNC. The DCV variant replaces that entire stack with Amazon DCV, which provides GPU-accelerated streaming, better image quality, and QUIC/UDP transport — no TigerVNC, noVNC, or websockify needed.

## Host Setup

The host EC2 instance must have the NVIDIA driver, Docker, and NVIDIA Container Toolkit installed before running this container.

Reference: [Install NVIDIA GPU driver, CUDA Toolkit, NVIDIA Container Toolkit on RHEL/Rocky Linux 8/9/10](https://repost.aws/articles/ARpmJcNiCtST2A3hrrM_4R4A/install-nvidia-gpu-driver-cuda-toolkit-nvidia-container-toolkit-on-amazon-ec2-instances-running-rhel-rocky-linux-8-9-10)

### Quick host setup (Rocky Linux 9)

```bash
# Update and install prerequisites
sudo dnf update -y
sudo dnf config-manager --set-enabled crb
sudo dnf install -y epel-release
sudo dnf install -y dkms kernel-devel kernel-modules-extra gcc make \
    vulkan-devel libglvnd-devel elfutils-libelf-devel

# Add NVIDIA repo and install driver
sudo dnf config-manager --add-repo \
    http://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
sudo dnf module enable -y nvidia-driver:open-dkms
sudo dnf install -y nvidia-open

# Install Docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker

# Install NVIDIA Container Toolkit
sudo dnf config-manager --add-repo \
    https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
sudo dnf install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify
sudo docker run --rm --runtime=nvidia --gpus all \
    public.ecr.aws/docker/library/rockylinux:9 nvidia-smi
```

## Build

```bash
docker build -f Dockerfile.rocky-nice-dcv -t rocky-dcv .
```

## Run

```bash
docker run --runtime=nvidia --gpus all --network host --cap-add SYS_PTRACE rocky-dcv
```

- `--network host` — DCV binds to port 8443 directly on the host
- `--cap-add SYS_PTRACE` — required for DCV's agent to inspect processes inside the container (without this, virtual sessions fail with "Unable to get real path" permission errors)

Connect via browser at `https://<host-ip>:8443` (accept the self-signed cert).

- Username: `rockyuser`
- Password: `rocky`

## What's Inside

| Component | Details |
|-----------|---------|
| Base image | `nvidia/cuda:12.4.0-runtime-rockylinux9` |
| Desktop | XFCE (lightweight) |
| Remote display | Amazon DCV 2024.0 (port 8443, HTTPS) |
| Application | Blender 5.0.1 with sample scene on desktop |
| GPU passthrough | Via `NVIDIA_VISIBLE_DEVICES=all` + NVIDIA Container Toolkit |

## DCV Configuration

The DCV server is configured in `/etc/dcv/dcv.conf` with:

- Virtual session mode (no physical display required)
- 60 FPS target
- QUIC/UDP frontend enabled (better streaming over lossy networks)
- DCV-GL disabled at session creation (`--gl off`) to avoid XFCE segfaults

## Files

- `Dockerfile.rocky-nice-dcv` — container image definition
- `start-dcv.sh` — entrypoint: starts D-Bus, DCV server, creates a virtual session with XFCE
- `Dockerfile.rocky` — alternative VNC-based version (TigerVNC + noVNC on ports 5901/6080)

## DCV vs VNC

| | DCV | VNC (Dockerfile.rocky) |
|---|---|---|
| Protocol | DCV (H.264/QUIC) | RFB + WebSocket |
| GPU encoding | Yes (NVENC) | No |
| Port | 8443 (HTTPS) | 5901 (VNC) / 6080 (noVNC) |
| Client | Browser or native DCV client | Browser (noVNC) or VNC client |
| Streaming quality | Higher (adaptive bitrate) | Basic |
| Complexity | Moderate | Simple |

## Troubleshooting & Debugging

### How we got here

Getting DCV running inside a container required solving several issues in sequence. Here's the full trail of problems and fixes, in order.

### Issue 1: "Could not create session — Could not get the system bus"

DCV requires D-Bus to communicate between the server and its agents. Containers don't run D-Bus by default.

Fix: start `dbus-daemon --system` before launching DCV in `start-dcv.sh`:
```bash
mkdir -p /run/dbus
dbus-daemon --system --fork
```

### Issue 2: Browser shows ERR_EMPTY_RESPONSE on port 8443

DCV server was running and responding to TLS handshakes, but returned HTTP 404 on `/`. The `nice-dcv-web-viewer` package was missing — only the server and GL packages were installed.

Fix: add `nice-dcv-web-viewer` to the RPM install list in the Dockerfile:
```dockerfile
dnf install -y /tmp/dcv-inst/nice-dcv-server-*.rpm \
               /tmp/dcv-inst/nice-dcv-gl-*.x86_64.rpm \
               /tmp/dcv-inst/nice-dcv-web-viewer-*.rpm \
               /tmp/dcv-inst/nice-xdcv-*.rpm
```

Diagnostic: `curl -vsk https://localhost:8443` showed a valid TLS handshake but `404 Not Found` with `Server: dcv`. That confirmed DCV was running but had no web content to serve.

### Issue 3: "No license available"

DCV is free on EC2 but needs to fetch a license file from an S3 bucket (`dcv-license.<region>`). The EC2 instance's IAM role didn't have `s3:GetObject` permission on that bucket.

Fix: attach this policy to the EC2 instance's IAM role:
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

Diagnostic: `grep -i licen /var/log/dcv/server.log` showed:
```
WARN license-manager - Unable to retrieve license object from AWS S3 bucket 'dcv-license.us-west-2': Access Denied
```

Important: the policy must be on the correct IAM role. Check which role the instance is using:
```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

### Issue 4: Login succeeds but just shows a spinner — no desktop

This was the hardest one. We tried several approaches:

**Attempt 1: Console session with Xvfb**

First approach was to run Xvfb (virtual framebuffer) on `:0`, start XFCE on it, then run DCV as a console session capturing that display. DCV connected and authenticated, but never rendered any frames. The DCV agent (`dcvagentlauncher`) started but couldn't capture from Xvfb — console sessions expect a real X server or Xdcv, not Xvfb.

**Attempt 2: Virtual session with XFCE — segfaults**

Switched to `dcv create-session --type virtual` which lets DCV manage its own X display via Xdcv. Used `startxfce4` as the init script. Result: `startxfce4` segfaulted immediately (exit code 139).

**Attempt 3: Launch XFCE components individually — still segfaults**

Tried launching `xfwm4`, `xfdesktop`, `xfce4-panel`, `xfce4-terminal` separately instead of through `startxfce4`. Every single XFCE binary segfaulted.

**Attempt 4: xterm as init script — works**

Tested with just `xterm` as the init script. Session stayed alive, xterm rendered fine. This confirmed the issue was specific to XFCE + DCV-GL, not the virtual session mechanism itself.

**Attempt 5: Disable DCV-GL — XFCE works**

The root cause: DCV-GL intercepts OpenGL calls via `LD_PRELOAD` to enable GPU-accelerated remote rendering. This interception was crashing every GTK/XFCE binary. The session log showed `DCV-GL enabled on 'rockyuser-session'` right before the segfaults.

Fix: create the session with `--gl off`:
```bash
dcv create-session --type virtual --owner rockyuser --user rockyuser \
    --init /usr/libexec/dcv/dcvstartxfce --gl off rockyuser-session
```

With DCV-GL disabled, XFCE starts cleanly. The desktop uses software rendering for the window manager, but DCV still handles the remote streaming efficiently.

**Attempt 6 (side issue): `--dcv-gl-disabled` is not a valid flag**

We initially tried `--dcv-gl-disabled` which caused `dcv create-session` to print its help text and exit non-zero. The correct flag is `--gl off`. Check valid flags with `dcv create-session --help`.

### Issue 5: "The dcvserver service is not running"

The `dcv create-session` command ran before the DCV server finished initializing. A fixed `sleep 3` wasn't reliable.

Fix: poll for readiness in the start script:
```bash
for i in $(seq 1 30); do
    if dcv list-sessions &>/dev/null; then
        break
    fi
    sleep 1
done
```

### Issue 6: "Address already in use" on port 8443

With `--network host`, if a previous container wasn't fully stopped, port 8443 stays bound. The new container's DCV server fails to start.

Fix: always clean up old containers before starting:
```bash
docker stop <old-container> && docker rm <old-container>
# Verify port is free
ss -tlnp | grep 8443
```

### Issue 7: Agent "Permission denied" on /proc

DCV's agent needs to read `/proc/<pid>` to verify the agent process identity. Docker's default seccomp/apparmor profile blocks this.

Log message:
```
WARN backend-handler - Connection requested by an unauthorized agent (PID: 146):
Unable to get real path for 146: Permission denied (os error 13)
```

Fix: add `--cap-add SYS_PTRACE` to the docker run command.

### Useful debug commands

```bash
# Check DCV server logs
docker exec <container> cat /var/log/dcv/server.log

# Check session launcher logs (virtual session startup)
docker exec <container> cat /var/log/dcv/dcv-xsession.rockyuser.rockyuser-session.log

# Check Xdcv (X server) logs
docker exec <container> cat /var/log/dcv/Xdcv.rockyuser.rockyuser-session.log

# Check agent logs
docker exec <container> cat /var/log/dcv/agent.rockyuser.rockyuser-session.log

# Check license status
docker exec <container> grep -i licen /var/log/dcv/server.log

# List active sessions
docker exec <container> dcv list-sessions

# Check if DCV is listening
ss -tlnp | grep 8443

# Test HTTPS response
curl -vsk https://localhost:8443

# Check running processes
docker exec <container> ps aux | grep -E "dcv|xfce|xfwm"
```

## References

- [Amazon DCV documentation](https://docs.aws.amazon.com/dcv/)
- [Amazon DCV downloads](https://www.amazondcv.com/)
- [Host GPU setup guide (RHEL/Rocky)](https://repost.aws/articles/ARpmJcNiCtST2A3hrrM_4R4A/install-nvidia-gpu-driver-cuda-toolkit-nvidia-container-toolkit-on-amazon-ec2-instances-running-rhel-rocky-linux-8-9-10)
- [AWS Batch + NICE DCV sample](https://github.com/aws-samples/aws-batch-using-nice-dcv)
- [Install GUI on RHEL/Rocky EC2](https://repost.aws/articles/AR4Nbl3SxTSIW3WpFSUJhzXg/install-gui-graphical-desktop-on-amazon-ec2-instances-running-rhel-rocky-linux-8-9)
