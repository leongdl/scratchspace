# Host Configuration: GPU Docker Instance Setup

## Overview

System configuration steps for running GPU-accelerated Docker containers (ComfyUI WanVideo, TRELLIS-2, etc.) on Amazon Linux 2023 with NVIDIA L40S.

## Verified Instance Specs

| Resource | Value |
|----------|-------|
| OS | Amazon Linux 2023 |
| Kernel | 6.1.161-183.298.amzn2023.x86_64 |
| GPU | NVIDIA L40S (48GB VRAM) |
| CUDA Driver | 580.126.09 |
| CUDA Version | 13.0 |
| RAM | 30GB |
| Disk | 512GB NVMe |
| CPUs | 4 |

## Step 1: Install and Start Docker

```bash
sudo dnf install docker -y
sudo systemctl start docker
sudo usermod -aG docker job-user
sudo usermod -aG docker ssm-user
```

## Step 2: Add job-user to Sudoers (Passwordless)

```bash
echo "job-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/job-user
```

## Step 3: Configure NVIDIA Container Toolkit Repository

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
```

## Step 4: Install NVIDIA Container Toolkit

Originally specified v1.18.1, upgraded to v1.18.2 due to BPF/cgroup device filter issue with driver 580.x.

```bash
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.2-1
sudo dnf install -y \
  nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}
```

## Step 5: Configure Docker NVIDIA Runtime

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

This writes the nvidia runtime to `/etc/docker/daemon.json`:

```json
{
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    }
}
```

## Step 6: Generate CDI Spec

Required for driver 580.x which hits a BPF device filter bug with the legacy `--gpus all` path.

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

## Step 7: Create Swap (Required for Large Model Loading)

The Wan 2.1 14B model (28GB) must be memory-mapped before loading to GPU. On g6e.xlarge (30GB RAM), this fails with `Cannot allocate memory` without swap.

```bash
sudo fallocate -l 32G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
```

This gives 30GB RAM + 32GB swap = 62GB virtual memory, enough to mmap the 28GB safetensors file. The model loads to GPU VRAM for inference — swap is only needed for the initial file read.

## Known Issue: `--gpus all` BPF Error with Driver 580.x

The standard `--gpus all` flag fails with NVIDIA driver 580.126.09 on kernel 6.1.x:

```
nvidia-container-cli: mount error: failed to add device rules:
unable to generate new device filter program from existing programs:
load program: invalid argument: last insn is not an exit or jmp
```

This is a known incompatibility between the legacy device cgroup filter and newer kernel BPF verifiers.

### Workaround: Use `--runtime=nvidia` Instead of `--gpus all`

Instead of:
```bash
docker run --gpus all ...
```

Use:
```bash
docker run --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  ...
```

This uses the nvidia container runtime directly and passes GPU configuration via environment variables, bypassing the broken BPF device filter path.

## Verification

```bash
# Test GPU access inside container
sudo docker run --rm \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

## Software Versions (Verified Working)

| Component | Version |
|-----------|---------|
| Docker | 25.0.14-1.amzn2023.0.1 |
| containerd | 2.1.5-1.amzn2023.0.5 |
| runc | 1.3.4-1.amzn2023.0.1 |
| nvidia-container-toolkit | 1.18.2-1 |
| libnvidia-container1 | 1.18.2-1 |
| NVIDIA Driver | 580.126.09 |
