#!/bin/bash
# Host configuration for Deadline Cloud workers running ComfyUI GUI + SSM sessions.
# Combines requirements from both the ComfyUI container pattern and the SSM managed node pattern.
#
# Requirements:
#   - Docker with NVIDIA runtime (for ComfyUI container)
#   - Passwordless sudo for job-user (for SSM agent install)
#   - Swap space for GPU instances with limited RAM
#
# Run this on the worker host (or via fleet host config) before submitting jobs.

set -e

echo "=== ComfyUI GUI + SSM Host Configuration ==="

# --- Passwordless sudo for job-user (required for SSM agent install) ---
if id "job-user" &>/dev/null; then
    echo "job-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/job-user
    echo "Passwordless sudo configured for job-user."
else
    echo "WARNING: job-user does not exist yet. Run this after the Deadline worker agent is installed."
fi

# --- Docker ---
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo dnf install -y docker
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker job-user 2>/dev/null || true
else
    echo "Docker already installed."
fi

# --- NVIDIA Container Toolkit ---
if ! command -v nvidia-ctk &>/dev/null; then
    echo "Installing NVIDIA Container Toolkit..."
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
      sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    sudo dnf install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo mkdir -p /etc/cdi && sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
    sudo systemctl restart docker
    echo "NVIDIA Container Toolkit installed and configured."
else
    echo "NVIDIA Container Toolkit already installed."
fi

# --- Swap space (32GB for instances with limited RAM like g6.xlarge) ---
if [ ! -f /swapfile ]; then
    echo "Creating 32GB swap file..."
    sudo dd if=/dev/zero of=/swapfile bs=1G count=32
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
    echo "Swap configured."
else
    echo "Swap file already exists."
fi

echo "=== Host configuration complete ==="
