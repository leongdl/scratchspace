#!/usr/bin/env python3
"""ComfyUI Container Builder - PyQt app for building Docker images with AI models."""

import sys
from pathlib import Path

from PyQt6.QtWidgets import QApplication

from ui.main_window import MainWindow


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("ComfyUI Container Builder")
    app.setOrganizationName("ComfyUI")
    
    window = MainWindow()
    window.show()
    
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
