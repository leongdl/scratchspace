"""Tab 1: Summary — Farm/Queue/Fleet selection with status indicators."""

from __future__ import annotations

from typing import Any

from PySide6.QtCore import QObject, QThread, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QGridLayout,
    QLabel,
    QVBoxLayout,
    QWidget,
)

from .aws_clients import (
    check_role_ecr_access,
    get_fleet_details,
    get_iam_client,
    get_queue_role_arn,
    list_farms,
    list_fleets,
    list_queues,
    load_app_config,
    load_deadline_default_farm,
    role_name_from_arn,
    save_app_config,
)


class StatusDot(QLabel):
    """A colored circle indicator."""

    def set_color(self, color: str) -> None:
        self.setStyleSheet(
            f"background-color: {color}; border-radius: 8px; min-width: 16px; "
            f"max-width: 16px; min-height: 16px; max-height: 16px;"
        )
        self.setToolTip(color)


class _QueueCheckWorker(QObject):
    """Background worker to check queue ECR access."""

    finished = Signal(str, str, str, bool)  # queue_id, role_arn, queue_name, has_ecr

    def __init__(self, dc: Any, iam: Any, farm_id: str, queue_id: str, queue_name: str) -> None:
        super().__init__()
        self._dc = dc
        self._iam = iam
        self._farm_id = farm_id
        self._queue_id = queue_id
        self._queue_name = queue_name

    def run(self) -> None:
        try:
            role_arn = get_queue_role_arn(self._dc, self._farm_id, self._queue_id)
            role_name = role_name_from_arn(role_arn)
            has_ecr = check_role_ecr_access(self._iam, role_name) if role_name else False
        except Exception:
            role_arn = ""
            has_ecr = False
        self.finished.emit(self._queue_id, role_arn, self._queue_name, has_ecr)


class _FleetCheckWorker(QObject):
    """Background worker to check fleet IAM + Docker status."""

    finished = Signal(str, str, str, bool, bool)  # fleet_id, farm_id, fleet_name, has_ecr, has_docker

    def __init__(self, dc: Any, iam: Any, farm_id: str, fleet_id: str, fleet_name: str) -> None:
        super().__init__()
        self._dc = dc
        self._iam = iam
        self._farm_id = farm_id
        self._fleet_id = fleet_id
        self._fleet_name = fleet_name

    def run(self) -> None:
        try:
            details = get_fleet_details(self._dc, self._farm_id, self._fleet_id)
            role_name = role_name_from_arn(details["roleArn"])
            has_ecr = check_role_ecr_access(self._iam, role_name) if role_name else False
            host_cfg = details.get("hostConfiguration", {}).get("scriptBody", "")
            has_docker = "docker" in host_cfg.lower() if host_cfg else False
        except Exception:
            has_ecr = False
            has_docker = False
        self.finished.emit(self._fleet_id, self._farm_id, self._fleet_name, has_ecr, has_docker)


class SummaryTab(QWidget):
    """Farm/Queue/Fleet selector with ECR and Docker status indicators."""

    queue_changed = Signal(str, str, str)  # queue_id, role_arn, queue_name
    fleet_changed = Signal(str, str, str)  # fleet_id, farm_id, fleet_name

    def __init__(self, deadline_client: Any) -> None:
        super().__init__()
        self._dc = deadline_client
        self._iam = get_iam_client()
        self._farms: list[dict[str, str]] = []
        self._queues: list[dict[str, str]] = []
        self._fleets: list[dict[str, str]] = []
        self._threads: list[QThread] = []

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(12)

        title = QLabel("Resource Overview")
        title.setStyleSheet("font-size: 16px; font-weight: bold; margin-bottom: 8px;")
        layout.addWidget(title)

        grid = QGridLayout()
        grid.setHorizontalSpacing(12)
        grid.setVerticalSpacing(10)

        # Row 0: Farm
        grid.addWidget(QLabel("Farm"), 0, 0)
        self.farm_combo = QComboBox()
        self.farm_combo.setMinimumWidth(350)
        grid.addWidget(self.farm_combo, 0, 1, 1, 4)

        # Row 1: Queue
        grid.addWidget(QLabel("Queue"), 1, 0)
        self.queue_combo = QComboBox()
        self.queue_combo.setMinimumWidth(350)
        grid.addWidget(self.queue_combo, 1, 1)
        grid.addWidget(QLabel("ECR"), 1, 2)
        self.queue_ecr_dot = StatusDot()
        self.queue_ecr_dot.set_color("gray")
        grid.addWidget(self.queue_ecr_dot, 1, 3)

        # Row 2: Fleet
        grid.addWidget(QLabel("Fleet"), 2, 0)
        self.fleet_combo = QComboBox()
        self.fleet_combo.setMinimumWidth(350)
        grid.addWidget(self.fleet_combo, 2, 1)
        grid.addWidget(QLabel("IAM"), 2, 2)
        self.fleet_iam_dot = StatusDot()
        self.fleet_iam_dot.set_color("gray")
        grid.addWidget(self.fleet_iam_dot, 2, 3)
        grid.addWidget(QLabel("Docker"), 2, 4)
        self.fleet_docker_dot = StatusDot()
        self.fleet_docker_dot.set_color("gray")
        grid.addWidget(self.fleet_docker_dot, 2, 5)

        layout.addLayout(grid)
        layout.addStretch()

        self.farm_combo.currentIndexChanged.connect(self._on_farm_changed)
        self.queue_combo.currentIndexChanged.connect(self._on_queue_changed)
        self.fleet_combo.currentIndexChanged.connect(self._on_fleet_changed)

        self._load_farms()

    def _load_farms(self) -> None:
        try:
            self._farms = list_farms(self._dc)
        except Exception:
            self._farms = []
        self.farm_combo.blockSignals(True)
        self.farm_combo.clear()
        for f in self._farms:
            self.farm_combo.addItem(f["displayName"], f["farmId"])
        app_cfg = load_app_config()
        default_farm = app_cfg.get("last_farm_id", "") or load_deadline_default_farm()
        idx = 0
        for i, f in enumerate(self._farms):
            if f["farmId"] == default_farm:
                idx = i
                break
        self.farm_combo.setCurrentIndex(idx)
        self.farm_combo.blockSignals(False)
        self._on_farm_changed()

    def _current_farm_id(self) -> str:
        idx = self.farm_combo.currentIndex()
        if idx < 0 or idx >= len(self._farms):
            return ""
        return self._farms[idx]["farmId"]

    def _on_farm_changed(self) -> None:
        farm_id = self._current_farm_id()
        if not farm_id:
            return
        self._save_selection()
        self._load_queues(farm_id)
        self._load_fleets(farm_id)

    def _load_queues(self, farm_id: str) -> None:
        try:
            self._queues = list_queues(self._dc, farm_id)
        except Exception:
            self._queues = []
        self.queue_combo.blockSignals(True)
        self.queue_combo.clear()
        for q in self._queues:
            self.queue_combo.addItem(q["displayName"], q["queueId"])
        app_cfg = load_app_config()
        last_queue = app_cfg.get("last_queue_id", "")
        idx = 0
        for i, q in enumerate(self._queues):
            if q["queueId"] == last_queue:
                idx = i
                break
        self.queue_combo.setCurrentIndex(idx)
        self.queue_combo.blockSignals(False)
        self._on_queue_changed()

    def _load_fleets(self, farm_id: str) -> None:
        try:
            self._fleets = list_fleets(self._dc, farm_id)
        except Exception:
            self._fleets = []
        self.fleet_combo.blockSignals(True)
        self.fleet_combo.clear()
        for f in self._fleets:
            self.fleet_combo.addItem(f["displayName"], f["fleetId"])
        app_cfg = load_app_config()
        last_fleet = app_cfg.get("last_fleet_id", "")
        idx = 0
        for i, f in enumerate(self._fleets):
            if f["fleetId"] == last_fleet:
                idx = i
                break
        self.fleet_combo.setCurrentIndex(idx)
        self.fleet_combo.blockSignals(False)
        self._on_fleet_changed()

    def _on_queue_changed(self) -> None:
        idx = self.queue_combo.currentIndex()
        if idx < 0 or idx >= len(self._queues):
            self.queue_ecr_dot.set_color("gray")
            return
        queue_id = self._queues[idx]["queueId"]
        queue_name = self._queues[idx]["displayName"]
        farm_id = self._current_farm_id()
        self._save_selection()
        self.queue_ecr_dot.set_color("gray")  # loading
        self._run_queue_check(farm_id, queue_id, queue_name)

    def _on_fleet_changed(self) -> None:
        idx = self.fleet_combo.currentIndex()
        if idx < 0 or idx >= len(self._fleets):
            self.fleet_iam_dot.set_color("gray")
            self.fleet_docker_dot.set_color("gray")
            return
        fleet_id = self._fleets[idx]["fleetId"]
        fleet_name = self._fleets[idx]["displayName"]
        farm_id = self._current_farm_id()
        self._save_selection()
        self.fleet_iam_dot.set_color("gray")
        self.fleet_docker_dot.set_color("gray")
        self._run_fleet_check(farm_id, fleet_id, fleet_name)

    def _run_queue_check(self, farm_id: str, queue_id: str, queue_name: str) -> None:
        thread = QThread()
        worker = _QueueCheckWorker(self._dc, self._iam, farm_id, queue_id, queue_name)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.finished.connect(self._on_queue_check_done)
        worker.finished.connect(thread.quit)
        thread.finished.connect(lambda: self._cleanup_thread(thread))
        self._threads.append(thread)
        thread.start()

    def _on_queue_check_done(self, queue_id: str, role_arn: str, queue_name: str, has_ecr: bool) -> None:
        self.queue_ecr_dot.set_color("green" if has_ecr else "red")
        self.queue_changed.emit(queue_id, role_arn, queue_name)

    def _run_fleet_check(self, farm_id: str, fleet_id: str, fleet_name: str) -> None:
        thread = QThread()
        worker = _FleetCheckWorker(self._dc, self._iam, farm_id, fleet_id, fleet_name)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.finished.connect(self._on_fleet_check_done)
        worker.finished.connect(thread.quit)
        thread.finished.connect(lambda: self._cleanup_thread(thread))
        self._threads.append(thread)
        thread.start()

    def _on_fleet_check_done(self, fleet_id: str, farm_id: str, fleet_name: str, has_ecr: bool, has_docker: bool) -> None:
        self.fleet_iam_dot.set_color("green" if has_ecr else "yellow")
        self.fleet_docker_dot.set_color("green" if has_docker else "red")
        self.fleet_changed.emit(fleet_id, farm_id, fleet_name)

    def _cleanup_thread(self, thread: QThread) -> None:
        if thread in self._threads:
            self._threads.remove(thread)

    def _save_selection(self) -> None:
        data = load_app_config()
        farm_id = self._current_farm_id()
        if farm_id:
            data["last_farm_id"] = farm_id
        q_idx = self.queue_combo.currentIndex()
        if 0 <= q_idx < len(self._queues):
            data["last_queue_id"] = self._queues[q_idx]["queueId"]
        f_idx = self.fleet_combo.currentIndex()
        if 0 <= f_idx < len(self._fleets):
            data["last_fleet_id"] = self._fleets[f_idx]["fleetId"]
        save_app_config(data)
