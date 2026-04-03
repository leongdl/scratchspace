"""Tests for host_config_builder module."""

from __future__ import annotations

import pytest

from app.host_config_builder import SWAP_SIZES, build_host_config, parse_host_config


class TestBuildHostConfig:
    def test_empty_config(self) -> None:
        result = build_host_config()
        assert result.startswith("#!/bin/bash")
        assert "set -e" in result
        assert "docker" not in result
        assert "NOPASSWD" not in result

    def test_docker_only(self) -> None:
        result = build_host_config(docker=True)
        assert "dnf install -y docker" in result
        assert "systemctl enable docker" in result
        assert "usermod -aG docker job-user" in result
        assert "NOPASSWD" not in result

    def test_sudo_only(self) -> None:
        result = build_host_config(sudo=True)
        assert "NOPASSWD:ALL" in result
        assert "docker" not in result.lower().replace("nopasswd", "")

    def test_nvidia_only(self) -> None:
        result = build_host_config(nvidia=True)
        assert "nvidia-container-toolkit" in result
        assert "nvidia-ctk runtime configure" in result
        assert "/etc/cdi" in result

    def test_swap_default_size(self) -> None:
        result = build_host_config(swap=True)
        assert "fallocate -l 32G /swapfile" in result
        assert "mkswap /swapfile" in result
        assert "swapon /swapfile" in result

    def test_swap_custom_size(self) -> None:
        result = build_host_config(swap=True, swap_size_gb=128)
        assert "fallocate -l 128G /swapfile" in result

    def test_all_options(self) -> None:
        result = build_host_config(
            docker=True, sudo=True, nvidia=True, swap=True, swap_size_gb=64
        )
        assert "dnf install -y docker" in result
        assert "NOPASSWD:ALL" in result
        assert "nvidia-container-toolkit" in result
        assert "fallocate -l 64G /swapfile" in result


class TestParseHostConfig:
    def test_empty_script(self) -> None:
        result = parse_host_config("")
        assert result["docker"] is False
        assert result["sudo"] is False
        assert result["nvidia"] is False
        assert result["swap"] is False
        assert result["swap_size_gb"] == 32

    def test_roundtrip_all_options(self) -> None:
        script = build_host_config(
            docker=True, sudo=True, nvidia=True, swap=True, swap_size_gb=96
        )
        result = parse_host_config(script)
        assert result["docker"] is True
        assert result["sudo"] is True
        assert result["nvidia"] is True
        assert result["swap"] is True
        assert result["swap_size_gb"] == 96

    def test_roundtrip_docker_only(self) -> None:
        script = build_host_config(docker=True)
        result = parse_host_config(script)
        assert result["docker"] is True
        assert result["sudo"] is False
        assert result["nvidia"] is False
        assert result["swap"] is False

    def test_roundtrip_each_swap_size(self) -> None:
        for size in SWAP_SIZES:
            script = build_host_config(swap=True, swap_size_gb=size)
            result = parse_host_config(script)
            assert result["swap"] is True
            assert result["swap_size_gb"] == size

    def test_parse_real_host_config(self) -> None:
        """Parse a script that looks like the comfy-demo host_config.sh."""
        script = """#!/bin/bash
set -e
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker job-user
echo "job-user ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/job-user
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
dnf install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
fallocate -l 32G /swapfile
mkswap /swapfile
swapon /swapfile
"""
        result = parse_host_config(script)
        assert result["docker"] is True
        assert result["sudo"] is True
        assert result["nvidia"] is True
        assert result["swap"] is True
        assert result["swap_size_gb"] == 32
