"""Main window for ComfyUI Container Builder."""

from PyQt6.QtWidgets import (
    QMainWindow, QTabWidget, QWidget, QVBoxLayout
)
from PyQt6.QtCore import Qt

from settings import Settings
from ui.build_tab import BuildTab
from ui.settings_tab import SettingsTab


class MainWindow(QMainWindow):
    """Main application window."""
    
    def __init__(self) -> None:
        super().__init__()
        self.settings = Settings.load()
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        self.setWindowTitle("ComfyUI Container Builder")
        self.setMinimumSize(800, 600)
        
        # Create tab widget
        tabs = QTabWidget()
        
        # Build tab
        self.build_tab = BuildTab(self.settings)
        tabs.addTab(self.build_tab, "Build")
        
        # Settings tab
        self.settings_tab = SettingsTab(self.settings)
        self.settings_tab.settings_changed.connect(self._on_settings_changed)
        tabs.addTab(self.settings_tab, "Settings")
        
        self.setCentralWidget(tabs)
    
    def _on_settings_changed(self) -> None:
        """Handle settings changes."""
        self.build_tab.update_settings(self.settings)
