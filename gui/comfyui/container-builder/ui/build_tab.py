"""Build tab for ComfyUI Container Builder."""

from pathlib import Path
from typing import TYPE_CHECKING

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QComboBox,
    QListWidget, QListWidgetItem, QPushButton, QLineEdit,
    QTextEdit, QGroupBox, QProgressBar, QMessageBox, QSplitter
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal

from models import AVAILABLE_MODELS, ModelInfo, get_categories, get_models_by_category
from docker_builder import generate_dockerfile, build_image, push_to_ecr

if TYPE_CHECKING:
    from settings import Settings


class BuildWorker(QThread):
    """Worker thread for Docker operations."""
    
    output = pyqtSignal(str)
    finished = pyqtSignal(bool, str)
    
    def __init__(self, operation: str, **kwargs) -> None:
        super().__init__()
        self.operation = operation
        self.kwargs = kwargs
    
    def run(self) -> None:
        if self.operation == "build":
            success, message = build_image(
                self.kwargs["dockerfile_path"],
                self.kwargs["image_tag"],
                on_output=lambda line: self.output.emit(line)
            )
        elif self.operation == "push":
            success, message = push_to_ecr(
                self.kwargs["image_tag"],
                self.kwargs["ecr_registry"],
                self.kwargs["ecr_region"],
                on_output=lambda line: self.output.emit(line)
            )
        else:
            success, message = False, f"Unknown operation: {self.operation}"
        
        self.finished.emit(success, message)


class BuildTab(QWidget):
    """Tab for building Docker images."""
    
    def __init__(self, settings: "Settings") -> None:
        super().__init__()
        self.settings = settings
        self.selected_models: list[ModelInfo] = []
        self.worker: BuildWorker | None = None
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        
        # Image tag input
        tag_layout = QHBoxLayout()
        tag_layout.addWidget(QLabel("Image Tag:"))
        self.tag_input = QLineEdit("comfyui-custom:latest")
        tag_layout.addWidget(self.tag_input)
        layout.addLayout(tag_layout)
        
        # Splitter for model selection and preview
        splitter = QSplitter(Qt.Orientation.Horizontal)
        
        # Left side: Model selection
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        
        # Category filter
        filter_layout = QHBoxLayout()
        filter_layout.addWidget(QLabel("Category:"))
        self.category_combo = QComboBox()
        self.category_combo.addItems(get_categories())
        self.category_combo.currentTextChanged.connect(self._on_category_changed)
        filter_layout.addWidget(self.category_combo)
        filter_layout.addStretch()
        left_layout.addLayout(filter_layout)
        
        # Available models list
        left_layout.addWidget(QLabel("Available Models:"))
        self.available_list = QListWidget()
        self.available_list.setSelectionMode(QListWidget.SelectionMode.ExtendedSelection)
        self._populate_available_models()
        left_layout.addWidget(self.available_list)
        
        # Add/Remove buttons
        btn_layout = QHBoxLayout()
        self.add_btn = QPushButton("Add →")
        self.add_btn.clicked.connect(self._add_models)
        self.remove_btn = QPushButton("← Remove")
        self.remove_btn.clicked.connect(self._remove_models)
        btn_layout.addWidget(self.add_btn)
        btn_layout.addWidget(self.remove_btn)
        left_layout.addLayout(btn_layout)
        
        splitter.addWidget(left_widget)
        
        # Right side: Selected models and preview
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        
        # Selected models
        right_layout.addWidget(QLabel("Selected Models:"))
        self.selected_list = QListWidget()
        right_layout.addWidget(self.selected_list)
        
        # Total size
        self.size_label = QLabel("Total size: 0.0 GB")
        right_layout.addWidget(self.size_label)
        
        splitter.addWidget(right_widget)
        splitter.setSizes([400, 400])
        
        layout.addWidget(splitter)
        
        # Dockerfile preview
        preview_group = QGroupBox("Generated Dockerfile")
        preview_layout = QVBoxLayout(preview_group)
        self.dockerfile_preview = QTextEdit()
        self.dockerfile_preview.setReadOnly(True)
        self.dockerfile_preview.setMaximumHeight(150)
        self.dockerfile_preview.setStyleSheet("font-family: monospace;")
        preview_layout.addWidget(self.dockerfile_preview)
        layout.addWidget(preview_group)
        
        # Build output
        output_group = QGroupBox("Build Output")
        output_layout = QVBoxLayout(output_group)
        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setMaximumHeight(120)
        output_layout.addWidget(self.output_text)
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)  # Indeterminate
        self.progress_bar.hide()
        output_layout.addWidget(self.progress_bar)
        layout.addWidget(output_group)
        
        # Action buttons
        action_layout = QHBoxLayout()
        self.build_btn = QPushButton("Build Image")
        self.build_btn.clicked.connect(self._build_image)
        self.push_btn = QPushButton("Push to ECR")
        self.push_btn.clicked.connect(self._push_to_ecr)
        action_layout.addStretch()
        action_layout.addWidget(self.build_btn)
        action_layout.addWidget(self.push_btn)
        layout.addLayout(action_layout)
        
        self._update_dockerfile_preview()
    
    def _populate_available_models(self) -> None:
        """Populate the available models list."""
        self.available_list.clear()
        category = self.category_combo.currentText()
        models = get_models_by_category(category)
        
        for model in models:
            item = QListWidgetItem(f"{model.name} ({model.size_gb:.1f} GB)")
            item.setData(Qt.ItemDataRole.UserRole, model)
            item.setToolTip(model.description)
            self.available_list.addItem(item)
    
    def _on_category_changed(self, category: str) -> None:
        """Handle category filter change."""
        self._populate_available_models()
    
    def _add_models(self) -> None:
        """Add selected models to the build list."""
        for item in self.available_list.selectedItems():
            model = item.data(Qt.ItemDataRole.UserRole)
            if model not in self.selected_models:
                self.selected_models.append(model)
        
        self._update_selected_list()
        self._update_dockerfile_preview()
    
    def _remove_models(self) -> None:
        """Remove selected models from the build list."""
        for item in self.selected_list.selectedItems():
            model = item.data(Qt.ItemDataRole.UserRole)
            if model in self.selected_models:
                self.selected_models.remove(model)
        
        self._update_selected_list()
        self._update_dockerfile_preview()
    
    def _update_selected_list(self) -> None:
        """Update the selected models list widget."""
        self.selected_list.clear()
        total_size = 0.0
        
        for model in self.selected_models:
            item = QListWidgetItem(f"{model.name} ({model.size_gb:.1f} GB)")
            item.setData(Qt.ItemDataRole.UserRole, model)
            self.selected_list.addItem(item)
            total_size += model.size_gb
        
        self.size_label.setText(f"Total size: {total_size:.1f} GB")
    
    def _update_dockerfile_preview(self) -> None:
        """Update the Dockerfile preview."""
        if not self.selected_models:
            self.dockerfile_preview.setPlainText("# Select models to generate Dockerfile")
            return
        
        content = generate_dockerfile(
            self.settings.base_image,
            self.selected_models,
            Path("/tmp/Dockerfile.preview")
        )
        self.dockerfile_preview.setPlainText(content)
    
    def _build_image(self) -> None:
        """Build the Docker image."""
        if not self.selected_models:
            QMessageBox.warning(self, "No Models", "Please select at least one model.")
            return
        
        # Generate Dockerfile
        dockerfile_path = Path(__file__).parent.parent / "generated" / "Dockerfile"
        generate_dockerfile(
            self.settings.base_image,
            self.selected_models,
            dockerfile_path
        )
        
        self._start_operation("build", 
            dockerfile_path=dockerfile_path,
            image_tag=self.tag_input.text()
        )
    
    def _push_to_ecr(self) -> None:
        """Push image to ECR."""
        if not self.settings.ecr_registry:
            QMessageBox.warning(self, "ECR Not Configured", 
                "Please configure ECR registry in Settings tab.")
            return
        
        self._start_operation("push",
            image_tag=self.tag_input.text(),
            ecr_registry=self.settings.ecr_registry,
            ecr_region=self.settings.ecr_region
        )
    
    def _start_operation(self, operation: str, **kwargs) -> None:
        """Start a Docker operation in a worker thread."""
        self.output_text.clear()
        self.progress_bar.show()
        self.build_btn.setEnabled(False)
        self.push_btn.setEnabled(False)
        
        self.worker = BuildWorker(operation, **kwargs)
        self.worker.output.connect(self._on_worker_output)
        self.worker.finished.connect(self._on_worker_finished)
        self.worker.start()
    
    def _on_worker_output(self, line: str) -> None:
        """Handle worker output."""
        self.output_text.append(line)
        # Auto-scroll to bottom
        scrollbar = self.output_text.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())
    
    def _on_worker_finished(self, success: bool, message: str) -> None:
        """Handle worker completion."""
        self.progress_bar.hide()
        self.build_btn.setEnabled(True)
        self.push_btn.setEnabled(True)
        
        if success:
            QMessageBox.information(self, "Success", message)
        else:
            QMessageBox.critical(self, "Error", message)
    
    def update_settings(self, settings: "Settings") -> None:
        """Update settings reference."""
        self.settings = settings
        self._update_dockerfile_preview()
