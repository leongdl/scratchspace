"""Settings tab for ComfyUI Container Builder."""

from typing import TYPE_CHECKING

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QComboBox, QPushButton, QGroupBox, QFormLayout, QMessageBox
)
from PyQt6.QtCore import pyqtSignal

if TYPE_CHECKING:
    from settings import Settings


AWS_REGIONS = [
    "us-east-1",
    "us-east-2", 
    "us-west-1",
    "us-west-2",
    "eu-west-1",
    "eu-west-2",
    "eu-central-1",
    "ap-northeast-1",
    "ap-southeast-1",
    "ap-southeast-2",
]


class SettingsTab(QWidget):
    """Tab for application settings."""
    
    settings_changed = pyqtSignal()
    
    def __init__(self, settings: "Settings") -> None:
        super().__init__()
        self.settings = settings
        self._setup_ui()
        self._load_settings()
    
    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        
        # ECR Settings
        ecr_group = QGroupBox("Amazon ECR Settings")
        ecr_layout = QFormLayout(ecr_group)
        
        self.ecr_registry_input = QLineEdit()
        self.ecr_registry_input.setPlaceholderText("123456789012.dkr.ecr.us-west-2.amazonaws.com")
        ecr_layout.addRow("ECR Registry:", self.ecr_registry_input)
        
        self.ecr_region_combo = QComboBox()
        self.ecr_region_combo.addItems(AWS_REGIONS)
        ecr_layout.addRow("AWS Region:", self.ecr_region_combo)
        
        layout.addWidget(ecr_group)
        
        # Docker Settings
        docker_group = QGroupBox("Docker Settings")
        docker_layout = QFormLayout(docker_group)
        
        self.base_image_input = QLineEdit()
        self.base_image_input.setPlaceholderText("comfyui-rocky:latest")
        docker_layout.addRow("Base Image:", self.base_image_input)
        
        self.default_tag_input = QLineEdit()
        self.default_tag_input.setPlaceholderText("latest")
        docker_layout.addRow("Default Tag:", self.default_tag_input)
        
        layout.addWidget(docker_group)
        
        # Spacer
        layout.addStretch()
        
        # Save button
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        self.save_btn = QPushButton("Save Settings")
        self.save_btn.clicked.connect(self._save_settings)
        btn_layout.addWidget(self.save_btn)
        layout.addLayout(btn_layout)
    
    def _load_settings(self) -> None:
        """Load settings into UI."""
        self.ecr_registry_input.setText(self.settings.ecr_registry)
        
        region_index = self.ecr_region_combo.findText(self.settings.ecr_region)
        if region_index >= 0:
            self.ecr_region_combo.setCurrentIndex(region_index)
        
        self.base_image_input.setText(self.settings.base_image)
        self.default_tag_input.setText(self.settings.default_tag)
    
    def _save_settings(self) -> None:
        """Save settings from UI."""
        self.settings.ecr_registry = self.ecr_registry_input.text().strip()
        self.settings.ecr_region = self.ecr_region_combo.currentText()
        self.settings.base_image = self.base_image_input.text().strip() or "comfyui-rocky:latest"
        self.settings.default_tag = self.default_tag_input.text().strip() or "latest"
        
        self.settings.save()
        self.settings_changed.emit()
        
        QMessageBox.information(self, "Settings Saved", "Settings have been saved successfully.")
