# ComfyUI Container Builder

PyQt6 app for building ComfyUI Docker images with pre-selected AI models.

## Install

```bash
pip install -r requirements.txt
```

## Run

```bash
python main.py
```

## Features

- Select from popular models (SD 1.5, SDXL, Flux, ControlNet, upscalers)
- Filter by category
- Auto-generates Dockerfile with selected models
- Build Docker images directly
- Push to Amazon ECR
- Persisted settings for ECR registry
