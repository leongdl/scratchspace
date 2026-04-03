"""Build fleet host configuration scripts from checkbox options."""

from __future__ import annotations

HEADER = """#!/bin/bash
set -e
"""

DOCKER_FRAGMENT = """
# --- Install Docker ---
dnf install -y docker
systemctl enable docker
systemctl start docker
if id "job-user" &>/dev/null; then
    usermod -aG docker job-user
fi
"""

SUDO_FRAGMENT = """
# --- Passwordless sudo for job-user ---
if id "job-user" &>/dev/null; then
    echo "job-user ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/job-user
fi
"""

NVIDIA_FRAGMENT = """
# --- NVIDIA Container Toolkit ---
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \\
    tee /etc/yum.repos.d/nvidia-container-toolkit.repo
dnf install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
mkdir -p /etc/cdi
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
systemctl restart docker
"""


def swap_fragment(size_gb: int) -> str:
    """Generate swap configuration fragment."""
    return f"""
# --- Swap ({size_gb}GB) ---
if [ ! -f /swapfile ]; then
    fallocate -l {size_gb}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | tee -a /etc/fstab
else
    swapon /swapfile 2>/dev/null || true
fi
"""


SWAP_SIZES = [32, 64, 96, 128]


def build_host_config(
    docker: bool = False,
    sudo: bool = False,
    nvidia: bool = False,
    swap: bool = False,
    swap_size_gb: int = 32,
) -> str:
    """Build a host config script from the selected options."""
    parts = [HEADER.strip()]
    if docker:
        parts.append(DOCKER_FRAGMENT.strip())
    if sudo:
        parts.append(SUDO_FRAGMENT.strip())
    if nvidia:
        parts.append(NVIDIA_FRAGMENT.strip())
    if swap:
        parts.append(swap_fragment(swap_size_gb).strip())
    return "\n\n".join(parts) + "\n"


def parse_host_config(script: str) -> dict[str, bool | int]:
    """Parse an existing host config script to determine which options are enabled."""
    result: dict[str, bool | int] = {
        "docker": False,
        "sudo": False,
        "nvidia": False,
        "swap": False,
        "swap_size_gb": 32,
    }
    if not script:
        return result
    result["docker"] = "dnf install" in script and "docker" in script
    result["sudo"] = "NOPASSWD" in script
    result["nvidia"] = "nvidia-container-toolkit" in script
    result["swap"] = "swapfile" in script
    # Try to extract swap size
    for size in reversed(SWAP_SIZES):
        if f"fallocate -l {size}G" in script:
            result["swap_size_gb"] = size
            break
    return result
