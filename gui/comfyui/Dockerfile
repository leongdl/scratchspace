# ComfyUI on Rocky Linux 9 with NVIDIA GPU support
# Designed for Deadline Cloud SMF workers with reverse tunnel access
FROM rockylinux:9

# Build arguments for customization
ARG PYTHON_VERSION=3.12
ARG CUDA_VERSION=12.4
ARG COMFYUI_VERSION=latest

# Install EPEL, development tools, and CUDA prerequisites
# Use --allowerasing to handle curl-minimal vs curl conflict in Rocky Linux 9
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
        libXrender \
        libSM \
        libXext \
        libgomp \
        && \
    dnf clean all

# Install NVIDIA CUDA toolkit (for GPU support)
RUN dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
    dnf install -y cuda-toolkit-12-4 && \
    dnf clean all

# Set up environment for CUDA
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Create comfyui user
RUN useradd -m -s /bin/bash comfyui && \
    echo "comfyui:comfyui" | chpasswd && \
    usermod -aG wheel comfyui

# Set up ComfyUI directory structure
WORKDIR /opt/comfyui

# Clone ComfyUI
RUN git clone https://github.com/Comfy-Org/ComfyUI.git /opt/comfyui && \
    chown -R comfyui:comfyui /opt/comfyui

# Create model directories with proper structure
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
    /opt/comfyui/models/upscale_models \
    /opt/comfyui/models/vae \
    /opt/comfyui/models/vae_approx \
    /opt/comfyui/input \
    /opt/comfyui/output \
    /opt/comfyui/custom_nodes && \
    chown -R comfyui:comfyui /opt/comfyui

# Install Python dependencies
USER comfyui
RUN python${PYTHON_VERSION} -m pip install --user --upgrade pip && \
    python${PYTHON_VERSION} -m pip install --user \
        torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    python${PYTHON_VERSION} -m pip install --user -r /opt/comfyui/requirements.txt

# Set Python path
ENV PATH=/home/comfyui/.local/bin:${PATH}

# Switch back to root for startup script
USER root

# Copy startup and tunnel scripts
COPY start-comfyui.sh /start-comfyui.sh
COPY reverse-tunnel.sh /reverse-tunnel.sh
RUN chmod +x /start-comfyui.sh /reverse-tunnel.sh

# Expose ComfyUI web interface port
EXPOSE 8188

# Volume mounts for models and outputs
VOLUME ["/opt/comfyui/models", "/opt/comfyui/input", "/opt/comfyui/output", "/opt/comfyui/custom_nodes"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8188/ || exit 1

CMD ["/start-comfyui.sh"]
