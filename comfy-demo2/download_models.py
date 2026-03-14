#!/usr/bin/env python3
"""Download HuggingFace models into ComfyUI model directories.
Token is read from /run/secrets/hf_token (Docker build secret mount)."""

import os
import shutil
from huggingface_hub import hf_hub_download

TOKEN_PATH = "/run/secrets/hf_token"
MODELS_ROOT = "/opt/comfyui/models"

def get_token():
    if os.path.exists(TOKEN_PATH):
        return open(TOKEN_PATH).read().strip()
    return os.environ.get("HF_TOKEN")

def dl(repo, filename, dest_dir, subfolder=None, token=None):
    """Download a single file from HF and move it to dest_dir."""
    os.makedirs(dest_dir, exist_ok=True)
    path = hf_hub_download(
        repo_id=repo,
        filename=filename,
        subfolder=subfolder,
        token=token,
    )
    basename = os.path.basename(filename)
    dest = os.path.join(dest_dir, basename)
    shutil.copy2(path, dest)
    size_gb = os.path.getsize(dest) / (1024**3)
    print(f"  ✓ {basename} ({size_gb:.2f} GB) → {dest_dir}")

def main():
    token = get_token()
    if not token:
        raise RuntimeError("No HF token found")

    print("=== LTX-2.3 ===")
    dl("Lightricks/LTX-2.3-fp8", "ltx-2.3-22b-dev-fp8.safetensors",
       f"{MODELS_ROOT}/checkpoints", token=token)
    dl("Lightricks/LTX-2.3", "ltx-2.3-22b-distilled-lora-384.safetensors",
       f"{MODELS_ROOT}/loras", token=token)
    dl("Lightricks/LTX-2.3", "ltx-2.3-spatial-upscaler-x2-1.0.safetensors",
       f"{MODELS_ROOT}/latent_upscale_models", token=token)
    dl("Comfy-Org/ltx-2", "gemma_3_12B_it_fp4_mixed.safetensors",
       f"{MODELS_ROOT}/text_encoders", subfolder="split_files/text_encoders", token=token)

    print("\n=== Qwen-Image-Edit-2511 ===")
    # Diffusion model from the Edit repo
    dl("Comfy-Org/Qwen-Image-Edit_ComfyUI", "qwen_image_edit_2511_bf16.safetensors",
       f"{MODELS_ROOT}/diffusion_models", subfolder="split_files/diffusion_models", token=token)
    # Text encoder and VAE are shared with the base Qwen-Image model
    dl("Comfy-Org/Qwen-Image_ComfyUI", "qwen_2.5_vl_7b_fp8_scaled.safetensors",
       f"{MODELS_ROOT}/text_encoders", subfolder="split_files/text_encoders", token=token)
    dl("Comfy-Org/Qwen-Image_ComfyUI", "qwen_image_vae.safetensors",
       f"{MODELS_ROOT}/vae", subfolder="split_files/vae", token=token)
    # Lightning 4-step LoRA from lightx2v
    dl("lightx2v/Qwen-Image-Edit-2511-Lightning", "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
       f"{MODELS_ROOT}/loras", token=token)

    print("\n=== Z-Image ===")
    # Z-Image files from Comfy-Org repackaged repo
    dl("Comfy-Org/z_image", "z_image_bf16.safetensors",
       f"{MODELS_ROOT}/diffusion_models", subfolder="split_files/diffusion_models", token=token)
    dl("Comfy-Org/z_image", "qwen_3_4b.safetensors",
       f"{MODELS_ROOT}/text_encoders", subfolder="split_files/text_encoders", token=token)
    dl("Comfy-Org/z_image", "ae.safetensors",
       f"{MODELS_ROOT}/vae", subfolder="split_files/vae", token=token)

    print("\nAll models downloaded successfully!")

if __name__ == "__main__":
    main()
