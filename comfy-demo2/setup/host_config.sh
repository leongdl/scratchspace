#!/bin/bash
# Host configuration for Deadline Cloud GPU workers running ComfyUI containers
# Run this on the worker host (or via fleet host config) before submitting jobs.
#
# Tested on: Amazon Linux 2023 (g6.xlarge, g6e.xlarge)
# Requires: NVIDIA driver already installed (comes with Deadline Cloud GPU AMIs)

set -e

echo "=== ComfyUI Worker Host Setup ==="

# --- Docker ---
echo "Installing Docker..."
sudo dnf install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$(whoami)"

# Allow job-user (Deadline worker user) to run docker
if id "job-user" &>/dev/null; then
    sudo usermod -aG docker job-user
    echo "job-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/job-user
fi

# --- NVIDIA Container Toolkit ---
echo "Installing NVIDIA Container Toolkit..."
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
    sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

sudo dnf install -y nvidia-container-toolkit

# Configure Docker to use NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Generate CDI spec (required for --runtime=nvidia on newer drivers)
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Restart Docker to pick up NVIDIA runtime
sudo systemctl restart docker

# --- Swap (recommended for <=16GB RAM instances like g6.xlarge) ---
# The 16GB S2V diffusion model needs to be mmap'd through CPU RAM before GPU load.
# Without swap, this can OOM-kill the container on 16GB RAM instances.
if [ ! -f /swapfile ]; then
    echo "Creating 32GB swap file..."
    sudo fallocate -l 32G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    # Persist across reboots
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
else
    echo "Swap file already exists"
    sudo swapon /swapfile 2>/dev/null || true
fi

# --- Verify ---
echo ""
echo "=== Verification ==="
echo "Docker: $(docker --version)"
echo "NVIDIA driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'not found')"
echo "GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo 'not found')"
echo "NVIDIA runtime: $(grep -c nvidia /etc/docker/daemon.json 2>/dev/null || echo '0') references in daemon.json"
echo "Swap: $(free -h | grep Swap | awk '{print $2}')"
echo ""
echo "Host setup complete. You can now build and run ComfyUI containers."
