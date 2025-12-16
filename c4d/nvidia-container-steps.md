# NVIDIA Container Toolkit Installation Steps (Amazon Linux / RHEL)

## Prerequisites
- NVIDIA GPU driver must be installed on the host first
- Verify with `nvidia-smi` before proceeding

## Step 1: Configure the NVIDIA Container Toolkit Repository
```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
```

## Step 2: Install the NVIDIA Container Toolkit
```bash
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.1-1
sudo dnf install -y \
    nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}
```

## Step 3: Configure Docker to Use NVIDIA Runtime
```bash
sudo nvidia-ctk runtime configure --runtime=docker
```

## Step 4: Restart Docker
```bash
sudo systemctl restart docker
```

## Verification
```bash
# Test GPU access in container
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

## Notes
- Completed on: 2025-12-16
- All 4 packages installed successfully
- Docker daemon.json updated at /etc/docker/daemon.json
- Host requires NVIDIA driver installation for `--gpus` flag to work
