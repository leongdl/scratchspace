# ComfyUI with Flux models pre-baked
# Build: docker build -f Dockerfile.flux -t comfyui-flux:latest .
# Note: Flux models require significant disk space (~24GB for schnell, ~48GB for dev)

FROM comfyui-rocky:latest

USER root

# Create Flux-specific directories
RUN mkdir -p \
    /opt/comfyui/models/unet \
    /opt/comfyui/models/clip \
    /opt/comfyui/models/vae

# Download Flux Schnell (faster, smaller model)
# Uncomment the model you want to use

# Flux Schnell UNET (~12GB)
RUN wget -q --show-progress -O /opt/comfyui/models/unet/flux1-schnell.safetensors \
    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors"

# Flux CLIP models
RUN wget -q --show-progress -O /opt/comfyui/models/clip/clip_l.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"

RUN wget -q --show-progress -O /opt/comfyui/models/clip/t5xxl_fp16.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"

# Flux VAE
RUN wget -q --show-progress -O /opt/comfyui/models/vae/ae.safetensors \
    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors"

# Download TAESD for fast previews
RUN wget -q --show-progress -O /opt/comfyui/models/vae_approx/taesd3_decoder.pth \
    "https://github.com/madebyollin/taesd/raw/main/taesd3_decoder.pth" || true

# Set proper ownership
RUN chown -R comfyui:comfyui /opt/comfyui/models

USER comfyui

# Enable TAESD previews by default
ENV PREVIEW_METHOD=taesd
