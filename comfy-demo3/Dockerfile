# ComfyUI on Rocky Linux 9 with NVIDIA GPU support (CUDA 12.6 + torch 2.7.0)
# Standalone base image — matches gui/comfyui/Dockerfile.trellis2 pattern
# Build: docker build -t comfyui-rocky:latest .
FROM nvidia/cuda:12.6.3-devel-rockylinux9

ARG PYTHON_VERSION=3.12

# Install system dependencies
RUN dnf install -y epel-release && \
    dnf update -y && \
    dnf groupinstall -y "Development Tools" && \
    dnf install -y --allowerasing \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-devel \
        git \
        wget \
        curl \
        procps-ng \
        sudo \
        openssh-clients \
        mesa-libGL \
        mesa-libGL-devel \
        mesa-libEGL-devel \
        libXrender \
        libSM \
        libXext \
        libgomp \
        && \
    dnf clean all

ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Create comfyui user
RUN useradd -m -s /bin/bash comfyui && \
    echo "comfyui:comfyui" | chpasswd && \
    usermod -aG wheel comfyui

# Clone ComfyUI
WORKDIR /opt/comfyui
RUN git clone https://github.com/Comfy-Org/ComfyUI.git /opt/comfyui && \
    chown -R comfyui:comfyui /opt/comfyui

# Create model directories
RUN mkdir -p \
    /opt/comfyui/models/checkpoints \
    /opt/comfyui/models/clip \
    /opt/comfyui/models/clip_vision \
    /opt/comfyui/models/controlnet \
    /opt/comfyui/models/diffusers \
    /opt/comfyui/models/embeddings \
    /opt/comfyui/models/gligen \
    /opt/comfyui/models/hypernetworks \
    /opt/comfyui/models/loras \
    /opt/comfyui/models/style_models \
    /opt/comfyui/models/unet \
    /opt/comfyui/models/diffusion_models \
    /opt/comfyui/models/text_encoders \
    /opt/comfyui/models/upscale_models \
    /opt/comfyui/models/vae \
    /opt/comfyui/models/vae_approx \
    /opt/comfyui/input \
    /opt/comfyui/output \
    /opt/comfyui/custom_nodes && \
    chown -R comfyui:comfyui /opt/comfyui

# Install Python dependencies with torch 2.7.0+cu126
USER comfyui
ENV PATH=/home/comfyui/.local/bin:${PATH}

RUN python${PYTHON_VERSION} -m pip install --user --upgrade pip && \
    python${PYTHON_VERSION} -m pip install --user \
        torch==2.7.0+cu126 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126 && \
    python${PYTHON_VERSION} -m pip install --user -r /opt/comfyui/requirements.txt

USER root

# Copy startup and tunnel scripts
COPY start-comfyui.sh /start-comfyui.sh
COPY reverse-tunnel.sh /reverse-tunnel.sh
RUN chmod +x /start-comfyui.sh /reverse-tunnel.sh

# Patch torch.AcceleratorError for torch < 2.8
# ComfyUI 0.16.4 references torch.AcceleratorError in its OOM handler, but
# this attribute was only added in torch 2.8. Patch the two call sites.
RUN sed -i "s/if isinstance(e, torch.AcceleratorError) and getattr(e, 'error_code', None) == 2:/if hasattr(torch, 'AcceleratorError') and isinstance(e, torch.AcceleratorError) and getattr(e, 'error_code', None) == 2:/" \
        /opt/comfyui/comfy/model_management.py && \
    sed -i "s/    except torch.AcceleratorError:/    except (torch.AcceleratorError if hasattr(torch, 'AcceleratorError') else RuntimeError):/" \
        /opt/comfyui/comfy/model_management.py

EXPOSE 8188

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8188/ || exit 1

CMD ["/start-comfyui.sh"]
