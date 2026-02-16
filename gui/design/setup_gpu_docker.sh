#!/bin/bash
# GPU Docker Host Setup for Amazon Linux 2023 + NVIDIA Driver 580.x
# Configures Docker with NVIDIA runtime (--runtime=nvidia workaround for BPF bug)
set -e

echo "=== Installing Docker ==="
sudo dnf install docker -y
sudo systemctl start docker
sudo usermod -aG docker job-user
sudo usermod -aG docker ssm-user

echo "=== Configuring job-user sudoers ==="
echo "job-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/job-user

echo "=== Adding NVIDIA Container Toolkit repo ==="
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

echo "=== Installing NVIDIA Container Toolkit 1.18.2 ==="
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.2-1
sudo dnf install -y \
  nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}

echo "=== Configuring Docker NVIDIA runtime ==="
sudo nvidia-ctk runtime configure --runtime=docker

echo "=== Generating CDI spec (workaround for driver 580.x BPF bug) ==="
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

echo "=== Creating 32GB swap (required for mmap of 28GB model files on 30GB RAM instances) ==="
if [ ! -f /swapfile ]; then
  sudo fallocate -l 32G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
fi
sudo swapon /swapfile 2>/dev/null || true
echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab

echo "=== Restarting Docker ==="
sudo systemctl restart docker

echo "=== Verifying GPU access ==="
sudo docker run --rm \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

echo "=== Setup complete ==="
