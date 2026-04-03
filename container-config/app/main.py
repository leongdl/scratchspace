"""Container Config — Deadline Cloud Docker Setup Tool."""

from __future__ import annotations

import sys

from PySide6.QtWidgets import QApplication, QMainWindow, QTabWidget

from .aws_clients import get_deadline_client, load_app_config
from .tab_fleet_config import FleetConfigTab
from .tab_queue_config import QueueConfigTab
from .tab_summary import SummaryTab

DARK_THEME = """
QMainWindow, QWidget {
    background-color: #1e1e2e;
    color: #cdd6f4;
    font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 13px;
}
QTabWidget::pane {
    border: 1px solid #45475a;
    border-radius: 4px;
    background-color: #1e1e2e;
}
QTabBar::tab {
    background-color: #313244;
    color: #a6adc8;
    padding: 8px 20px;
    border: 1px solid #45475a;
    border-bottom: none;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
    margin-right: 2px;
}
QTabBar::tab:selected {
    background-color: #1e1e2e;
    color: #cdd6f4;
    border-bottom: 2px solid #89b4fa;
}
QTabBar::tab:hover {
    background-color: #45475a;
}
QComboBox {
    background-color: #313244;
    color: #cdd6f4;
    border: 1px solid #45475a;
    border-radius: 4px;
    padding: 6px 10px;
    min-height: 20px;
}
QComboBox::drop-down {
    border: none;
    width: 24px;
}
QComboBox QAbstractItemView {
    background-color: #313244;
    color: #cdd6f4;
    selection-background-color: #45475a;
    border: 1px solid #585b70;
}
QPushButton {
    background-color: #89b4fa;
    color: #1e1e2e;
    border: none;
    border-radius: 4px;
    padding: 8px 16px;
    font-weight: bold;
}
QPushButton:hover {
    background-color: #74c7ec;
}
QPushButton:pressed {
    background-color: #585b70;
}
QTextEdit {
    background-color: #181825;
    color: #a6e3a1;
    border: 1px solid #45475a;
    border-radius: 4px;
    padding: 8px;
    font-family: "Courier New", monospace;
    font-size: 12px;
}
QCheckBox {
    spacing: 8px;
    color: #cdd6f4;
}
QCheckBox::indicator {
    width: 16px;
    height: 16px;
    border: 1px solid #585b70;
    border-radius: 3px;
    background-color: #313244;
}
QCheckBox::indicator:checked {
    background-color: #89b4fa;
    border-color: #89b4fa;
}
QLabel {
    color: #cdd6f4;
}
QGridLayout {
    margin: 12px;
}
"""


class MainWindow(QMainWindow):
    """Main application window with three tabs."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Deadline Cloud — Container Config")
        self.setMinimumSize(900, 650)

        app_cfg = load_app_config()
        region = app_cfg.get("region", "us-west-2")
        dc = get_deadline_client(region)

        tabs = QTabWidget()
        self.setCentralWidget(tabs)

        self.summary_tab = SummaryTab(dc)
        tabs.addTab(self.summary_tab, "Summary")

        self.queue_tab = QueueConfigTab(region)
        tabs.addTab(self.queue_tab, "Queue Config")

        self.fleet_tab = FleetConfigTab(dc)
        tabs.addTab(self.fleet_tab, "Fleet Config")

        self.summary_tab.queue_changed.connect(self.queue_tab.on_queue_changed)
        self.summary_tab.fleet_changed.connect(self.fleet_tab.on_fleet_changed)


def main() -> None:
    """Entry point."""
    app = QApplication(sys.argv)
    app.setStyleSheet(DARK_THEME)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
