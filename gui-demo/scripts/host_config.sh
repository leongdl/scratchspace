#!/bin/bash
 
# Install and start Docker
dnf install docker -y
sudo systemctl start docker
sudo usermod -aG docker job-user
 
# Add job-user to sudoers (passwordless)
echo "job-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/job-user
 
# Configure NVIDIA Container Toolkit repository
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
 
# Install NVIDIA Container Toolkit
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.2-1
sudo dnf install -y \
    nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}

# Configure Docker to use NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Generate CDI spec — required for driver 580.x which hits a BPF device filter
# bug with the legacy --gpus all path. Use --runtime=nvidia instead.
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Restart Docker to apply NVIDIA runtime config
sudo systemctl restart docker

# # Create 32GB swap (uncomment if loading large models e.g. Wan 2.1 14B on <=30GB RAM)
# sudo fallocate -l 32G /swapfile
# sudo chmod 600 /swapfile
# sudo mkswap /swapfile
# sudo swapon /swapfile
# echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab