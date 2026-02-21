# Job Bundle

Deadline Cloud job template and submit script for launching a VNC desktop session on an SMF worker.

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | Deadline job template — pulls Docker image, starts VNC, establishes reverse SSH tunnel |
| `submit.sh` | Convenience script to submit the job with default parameters |

## Prerequisites

- Docker image pushed to ECR (see `../docker/README.md`)
- Infrastructure provisioned (see `../scripts/README.md`)
- SSH private key (`vnc_tunnel_key`) placed in this directory — the job attaches it for the reverse tunnel
- VPC Lattice resource config attached to your Deadline fleet

## Submit

```bash
# Default parameters
bash submit.sh

# Custom session duration and proxy
EC2_PROXY_HOST=10.0.0.65 SESSION_DURATION=7200 bash submit.sh
```

## What the Job Does

1. Pulls the Rocky VNC image from ECR
2. Starts the container with `--network host` and GPU access
3. Waits for noVNC to be ready on port 6080
4. Opens a reverse SSH tunnel through VPC Lattice to the EC2 bastion
5. Monitors the session, auto-restarts the tunnel if it drops
6. Cleans up after the configured duration (default 1 hour)

## Docker Startup Flags

The container is started with these flags for GPU access:

```bash
docker run -d \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  --network host \
  --name rocky-vnc-desktop \
  <image>
```

- `--runtime=nvidia` — uses the NVIDIA container runtime instead of `--gpus all` (required workaround for driver 570.x/580.x BPF bug)
- `NVIDIA_VISIBLE_DEVICES=all` — exposes all GPUs to the container
- `NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics` — enables CUDA compute, nvidia-smi, and OpenGL/Vulkan graphics
- `--network host` — shares the host network so noVNC on port 6080 is directly accessible for the reverse tunnel

The host must have the NVIDIA container toolkit installed and configured via `host_config.sh`.
