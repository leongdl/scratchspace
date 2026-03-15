#!/usr/bin/env python3
"""Download models for anime.json + anime2.json workflows.

Supports two sources:
  - HuggingFace (public, no token needed)
  - CivitAI (requires CIVITAI_TOKEN via /run/secrets/civitai_token or env)

Usage in Dockerfile:
  RUN --mount=type=secret,id=civitai_token \
      python3.12 /tmp/download_models.py
"""

import os
import subprocess

MODELS_ROOT = "/opt/comfyui/models"


def get_civitai_token():
    token_path = "/run/secrets/civitai_token"
    if os.path.exists(token_path):
        return open(token_path).read().strip()
    return os.environ.get("CIVITAI_TOKEN")


def dl_hf(repo, filename, dest_dir, subfolder=None):
    """Download a file from HuggingFace using wget."""
    os.makedirs(dest_dir, exist_ok=True)
    if subfolder:
        url = f"https://huggingface.co/{repo}/resolve/main/{subfolder}/{filename}"
    else:
        url = f"https://huggingface.co/{repo}/resolve/main/{filename}"
    dest = os.path.join(dest_dir, os.path.basename(filename))
    print(f"  Downloading {filename} from {repo}...")
    subprocess.run(
        ["wget", "-q", "--show-progress", "-O", dest, url],
        check=True,
    )
    size_gb = os.path.getsize(dest) / (1024**3)
    print(f"  ✓ {os.path.basename(dest)} ({size_gb:.2f} GB) → {dest_dir}")


def dl_civitai(version_id, filename, dest_dir, token=None):
    """Download a file from CivitAI API using wget."""
    os.makedirs(dest_dir, exist_ok=True)
    url = f"https://civitai.com/api/download/models/{version_id}"
    if token:
        url += f"?token={token}"
    dest = os.path.join(dest_dir, filename)
    print(f"  Downloading {filename} from CivitAI (version {version_id})...")
    subprocess.run(
        ["wget", "-q", "--show-progress", "--content-disposition", "-O", dest, url],
        check=True,
    )
    size_gb = os.path.getsize(dest) / (1024**3)
    print(f"  ✓ {filename} ({size_gb:.2f} GB) → {dest_dir}")


def main():
    civitai_token = get_civitai_token()

    # =================================================================
    # anime2.json — Anima preview2 (ACE architecture, txt2img)
    # Source: circlestone-labs/Anima (HuggingFace, public)
    # =================================================================
    print("\n=== Anima preview2 (anime2.json) ===")

    dl_hf("circlestone-labs/Anima",
          "anima-preview2.safetensors",
          f"{MODELS_ROOT}/diffusion_models",
          subfolder="split_files/diffusion_models")

    dl_hf("circlestone-labs/Anima",
          "qwen_3_06b_base.safetensors",
          f"{MODELS_ROOT}/text_encoders",
          subfolder="split_files/text_encoders")

    dl_hf("circlestone-labs/Anima",
          "qwen_image_vae.safetensors",
          f"{MODELS_ROOT}/vae",
          subfolder="split_files/vae")

    # =================================================================
    # anime.json — waiNSFWIllustrious v11.0 (SDXL, unsampler workflow)
    # Source: CivitAI model 827184, version 1410435
    # =================================================================
    print("\n=== waiNSFWIllustrious v11.0 (anime.json) ===")

    if not civitai_token:
        print("  ⚠ No CIVITAI_TOKEN found — skipping CivitAI downloads")
        print("  Set CIVITAI_TOKEN env or mount /run/secrets/civitai_token")
    else:
        dl_civitai(1410435,
                   "waiNSFWIllustrious_v110.safetensors",
                   f"{MODELS_ROOT}/checkpoints",
                   token=civitai_token)

    # =================================================================
    # anime.json — ControlNet Union SDXL ProMax
    # Source: xinsir/controlnet-union-sdxl-1.0 (HuggingFace, public)
    # =================================================================
    print("\n=== ControlNet Union SDXL ProMax (anime.json) ===")

    dl_hf("xinsir/controlnet-union-sdxl-1.0",
          "diffusion_pytorch_model_promax.safetensors",
          f"{MODELS_ROOT}/controlnet")

    # Rename to match the filename the DAG expects
    src = f"{MODELS_ROOT}/controlnet/diffusion_pytorch_model_promax.safetensors"
    dst = f"{MODELS_ROOT}/controlnet/xinsir-controlnet-union-sdxl-promax.safetensors"
    if os.path.exists(src):
        os.rename(src, dst)
        print(f"  Renamed → {os.path.basename(dst)}")

    print("\nAll model downloads complete!")


if __name__ == "__main__":
    main()
