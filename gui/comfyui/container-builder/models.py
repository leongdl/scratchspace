"""Model definitions for ComfyUI container builder."""

from dataclasses import dataclass


@dataclass
class ModelInfo:
    """Information about a downloadable model."""
    name: str
    category: str
    url: str
    filename: str
    destination: str  # Relative path under /opt/comfyui/models/
    size_gb: float
    description: str


# Popular models organized by category
AVAILABLE_MODELS: list[ModelInfo] = [
    # Stable Diffusion 1.5
    ModelInfo(
        name="SD 1.5 (Pruned)",
        category="Checkpoints - SD 1.5",
        url="https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors",
        filename="v1-5-pruned-emaonly.safetensors",
        destination="checkpoints",
        size_gb=4.0,
        description="Stable Diffusion 1.5 base model, pruned for inference"
    ),
    
    # SDXL
    ModelInfo(
        name="SDXL Base 1.0",
        category="Checkpoints - SDXL",
        url="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors",
        filename="sd_xl_base_1.0.safetensors",
        destination="checkpoints",
        size_gb=6.9,
        description="SDXL base model for high-resolution image generation"
    ),
    ModelInfo(
        name="SDXL Refiner 1.0",
        category="Checkpoints - SDXL",
        url="https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors",
        filename="sd_xl_refiner_1.0.safetensors",
        destination="checkpoints",
        size_gb=6.1,
        description="SDXL refiner for detail enhancement"
    ),
    ModelInfo(
        name="SDXL VAE",
        category="VAE - SDXL",
        url="https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors",
        filename="sdxl_vae.safetensors",
        destination="vae",
        size_gb=0.3,
        description="SDXL VAE for improved image quality"
    ),
    
    # Flux
    ModelInfo(
        name="Flux Schnell",
        category="Checkpoints - Flux",
        url="https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors",
        filename="flux1-schnell.safetensors",
        destination="unet",
        size_gb=12.0,
        description="Flux Schnell - fast inference model"
    ),
    ModelInfo(
        name="Flux CLIP-L",
        category="CLIP - Flux",
        url="https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors",
        filename="clip_l.safetensors",
        destination="clip",
        size_gb=0.2,
        description="CLIP-L text encoder for Flux"
    ),
    ModelInfo(
        name="Flux T5-XXL (FP16)",
        category="CLIP - Flux",
        url="https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors",
        filename="t5xxl_fp16.safetensors",
        destination="clip",
        size_gb=9.8,
        description="T5-XXL text encoder for Flux (FP16)"
    ),
    ModelInfo(
        name="Flux VAE",
        category="VAE - Flux",
        url="https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors",
        filename="ae.safetensors",
        destination="vae",
        size_gb=0.3,
        description="Flux autoencoder VAE"
    ),
    
    # ControlNet
    ModelInfo(
        name="ControlNet Canny (SD 1.5)",
        category="ControlNet",
        url="https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny.pth",
        filename="control_v11p_sd15_canny.pth",
        destination="controlnet",
        size_gb=1.4,
        description="ControlNet for edge detection guidance"
    ),
    ModelInfo(
        name="ControlNet Depth (SD 1.5)",
        category="ControlNet",
        url="https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11f1p_sd15_depth.pth",
        filename="control_v11f1p_sd15_depth.pth",
        destination="controlnet",
        size_gb=1.4,
        description="ControlNet for depth map guidance"
    ),
    ModelInfo(
        name="ControlNet OpenPose (SD 1.5)",
        category="ControlNet",
        url="https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.pth",
        filename="control_v11p_sd15_openpose.pth",
        destination="controlnet",
        size_gb=1.4,
        description="ControlNet for pose guidance"
    ),
    
    # Upscalers
    ModelInfo(
        name="RealESRGAN x4",
        category="Upscalers",
        url="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
        filename="RealESRGAN_x4plus.pth",
        destination="upscale_models",
        size_gb=0.06,
        description="4x upscaler for realistic images"
    ),
    ModelInfo(
        name="RealESRGAN x4 Anime",
        category="Upscalers",
        url="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth",
        filename="RealESRGAN_x4plus_anime_6B.pth",
        destination="upscale_models",
        size_gb=0.02,
        description="4x upscaler optimized for anime"
    ),
    
    # TAESD Previews
    ModelInfo(
        name="TAESD Decoder (SD 1.5)",
        category="Preview Decoders",
        url="https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth",
        filename="taesd_decoder.pth",
        destination="vae_approx",
        size_gb=0.005,
        description="Fast preview decoder for SD 1.5"
    ),
    ModelInfo(
        name="TAESD Decoder (SDXL)",
        category="Preview Decoders",
        url="https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth",
        filename="taesdxl_decoder.pth",
        destination="vae_approx",
        size_gb=0.005,
        description="Fast preview decoder for SDXL"
    ),
    ModelInfo(
        name="TAESD Decoder (SD3/Flux)",
        category="Preview Decoders",
        url="https://github.com/madebyollin/taesd/raw/main/taesd3_decoder.pth",
        filename="taesd3_decoder.pth",
        destination="vae_approx",
        size_gb=0.005,
        description="Fast preview decoder for SD3/Flux"
    ),
]


def get_categories() -> list[str]:
    """Get unique categories from available models."""
    categories = sorted(set(m.category for m in AVAILABLE_MODELS))
    return ["All"] + categories


def get_models_by_category(category: str) -> list[ModelInfo]:
    """Get models filtered by category."""
    if category == "All":
        return AVAILABLE_MODELS
    return [m for m in AVAILABLE_MODELS if m.category == category]
