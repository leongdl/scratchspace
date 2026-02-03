"""Settings management for ComfyUI container builder."""

import json
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any


@dataclass
class Settings:
    """Application settings."""
    ecr_registry: str = ""
    ecr_region: str = "us-west-2"
    base_image: str = "comfyui-rocky:latest"
    default_tag: str = "latest"
    dockerfile_path: str = "../Dockerfile"
    
    @classmethod
    def get_settings_path(cls) -> Path:
        """Get the settings file path."""
        config_dir = Path.home() / ".config" / "comfyui-container-builder"
        config_dir.mkdir(parents=True, exist_ok=True)
        return config_dir / "settings.json"
    
    @classmethod
    def load(cls) -> "Settings":
        """Load settings from disk."""
        settings_path = cls.get_settings_path()
        if settings_path.exists():
            try:
                with open(settings_path) as f:
                    data = json.load(f)
                return cls(**data)
            except (json.JSONDecodeError, TypeError):
                pass
        return cls()
    
    def save(self) -> None:
        """Save settings to disk."""
        settings_path = self.get_settings_path()
        with open(settings_path, "w") as f:
            json.dump(asdict(self), f, indent=2)
