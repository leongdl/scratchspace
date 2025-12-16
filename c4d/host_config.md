#!/bin/bash
echo "Hello Demo Queued"

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
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.1-1
sudo dnf install -y \
    nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}

# Configure Docker to use NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Restart Docker to apply NVIDIA runtime config
sudo systemctl restart docker

# Login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 224071664257.dkr.ecr.us-west-2.amazonaws.com
# Pull the container
# docker pull 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex:latest
#docker pull 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:latest
#docker pull 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:houdini-latest
#docker pull 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:nuke16-latest
exit 0