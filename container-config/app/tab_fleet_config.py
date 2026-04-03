"""Tab 3: Fleet Config — Host configuration script builder."""

from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .aws_clients import get_fleet_details, update_fleet_host_config
from .host_config_builder import SWAP_SIZES, build_host_config, parse_host_config


class FleetConfigTab(QWidget):
    """Fleet host configuration script builder with checkboxes."""

    def __init__(self, deadline_client: Any) -> None:
        super().__init__()
        self._dc = deadline_client
        self._farm_id = ""
        self._fleet_id = ""
        self._fleet_name = ""

        layout = QVBoxLayout(self)

        self.fleet_label = QLabel("Fleet: (none selected)")
        layout.addWidget(self.fleet_label)

        layout.addWidget(QLabel("Host Configuration Options:"))

        self.docker_cb = QCheckBox("Install Docker")
        self.docker_cb.stateChanged.connect(self._rebuild_script)
        layout.addWidget(self.docker_cb)

        self.sudo_cb = QCheckBox("Job-user passwordless sudo")
        self.sudo_cb.stateChanged.connect(self._rebuild_script)
        layout.addWidget(self.sudo_cb)

        self.nvidia_cb = QCheckBox("NVIDIA Container Toolkit")
        self.nvidia_cb.stateChanged.connect(self._rebuild_script)
        layout.addWidget(self.nvidia_cb)

        # Swap row: checkbox + size dropdown
        swap_row = QHBoxLayout()
        self.swap_cb = QCheckBox("Swap")
        self.swap_cb.stateChanged.connect(self._rebuild_script)
        swap_row.addWidget(self.swap_cb)
        self.swap_combo = QComboBox()
        for size in SWAP_SIZES:
            self.swap_combo.addItem(f"{size}GB", size)
        self.swap_combo.currentIndexChanged.connect(self._rebuild_script)
        swap_row.addWidget(self.swap_combo)
        swap_row.addStretch()
        layout.addLayout(swap_row)

        # Script preview
        layout.addWidget(QLabel("Generated Host Config Script:"))
        self.script_text = QTextEdit()
        self.script_text.setReadOnly(True)
        self.script_text.setFontFamily("Arial")
        layout.addWidget(self.script_text)

        # Save button
        self.save_btn = QPushButton("Save")
        self.save_btn.clicked.connect(self._save)
        layout.addWidget(self.save_btn)

    def on_fleet_changed(self, fleet_id: str, farm_id: str, fleet_name: str) -> None:
        """Called when Tab 1 fleet selection changes."""
        self._fleet_id = fleet_id
        self._farm_id = farm_id
        self._fleet_name = fleet_name
        self.fleet_label.setText(f"Fleet: {fleet_name}")
        self._load_current_config()

    def _load_current_config(self) -> None:
        """Load the fleet's current host config and set checkboxes."""
        if not self._farm_id or not self._fleet_id:
            return
        try:
            details = get_fleet_details(self._dc, self._farm_id, self._fleet_id)
            script = details.get("hostConfiguration", {}).get("scriptBody", "")
        except Exception:
            script = ""

        opts = parse_host_config(script)

        # Block signals while setting checkboxes to avoid redundant rebuilds
        for cb in (self.docker_cb, self.sudo_cb, self.nvidia_cb, self.swap_cb):
            cb.blockSignals(True)
        self.swap_combo.blockSignals(True)

        self.docker_cb.setChecked(bool(opts["docker"]))
        self.sudo_cb.setChecked(bool(opts["sudo"]))
        self.nvidia_cb.setChecked(bool(opts["nvidia"]))
        self.swap_cb.setChecked(bool(opts["swap"]))

        swap_size = int(opts.get("swap_size_gb", 32))
        idx = SWAP_SIZES.index(swap_size) if swap_size in SWAP_SIZES else 0
        self.swap_combo.setCurrentIndex(idx)

        for cb in (self.docker_cb, self.sudo_cb, self.nvidia_cb, self.swap_cb):
            cb.blockSignals(False)
        self.swap_combo.blockSignals(False)

        self._rebuild_script()

    def _rebuild_script(self) -> None:
        """Regenerate the script preview from current checkbox state."""
        swap_size = self.swap_combo.currentData() or 32
        script = build_host_config(
            docker=self.docker_cb.isChecked(),
            sudo=self.sudo_cb.isChecked(),
            nvidia=self.nvidia_cb.isChecked(),
            swap=self.swap_cb.isChecked(),
            swap_size_gb=swap_size,
        )
        self.script_text.setPlainText(script)

    def _save(self) -> None:
        """Persist the host config to the fleet."""
        if not self._farm_id or not self._fleet_id:
            QMessageBox.warning(self, "No Fleet", "No fleet selected.")
            return
        script = self.script_text.toPlainText()
        try:
            update_fleet_host_config(self._dc, self._farm_id, self._fleet_id, script)
            QMessageBox.information(self, "Saved", f"Host config saved to fleet {self._fleet_name}.")
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to save host config: {e}")
