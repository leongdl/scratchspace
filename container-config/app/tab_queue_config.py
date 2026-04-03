"""Tab 2: Queue Config — IAM policy and ECR repo management."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .aws_clients import (
    build_ecr_policy,
    get_ecr_client,
    get_iam_client,
    get_inline_ecr_policy,
    get_repo_arns_in_policy,
    list_ecr_repos,
    role_name_from_arn,
    save_ecr_policy,
)

if TYPE_CHECKING:
    pass


class QueueConfigTab(QWidget):
    """Queue IAM policy viewer and ECR repo access manager."""

    def __init__(self, region: str = "us-west-2") -> None:
        super().__init__()
        self._iam = get_iam_client()
        self._ecr = get_ecr_client(region)
        self._role_arn = ""
        self._role_name = ""
        self._queue_name = ""
        self._repos: list[dict[str, str]] = []
        self._policy_repo_arns: set[str] = set()
        self._pending_repo_arns: set[str] = set()

        layout = QVBoxLayout(self)

        # Queue info
        self.queue_label = QLabel("Queue: (none selected)")
        layout.addWidget(self.queue_label)
        self.role_label = QLabel("Role: —")
        layout.addWidget(self.role_label)

        # ECR repo selector
        layout.addWidget(QLabel("ECR Repositories:"))
        ecr_row = QHBoxLayout()
        self.repo_combo = QComboBox()
        self.repo_combo.setMinimumWidth(400)
        ecr_row.addWidget(self.repo_combo)
        self.add_btn = QPushButton("Add to Policy")
        self.add_btn.clicked.connect(self._add_repo)
        ecr_row.addWidget(self.add_btn)
        self.remove_btn = QPushButton("Remove from Policy")
        self.remove_btn.clicked.connect(self._remove_repo)
        ecr_row.addWidget(self.remove_btn)
        ecr_row.addStretch()
        layout.addLayout(ecr_row)

        # Policy viewer
        layout.addWidget(QLabel("Current IAM Policy (DeadlineECRAccess):"))
        self.policy_text = QTextEdit()
        self.policy_text.setReadOnly(True)
        self.policy_text.setFontFamily("Courier")
        layout.addWidget(self.policy_text)

        # Save button
        self.save_btn = QPushButton("Save")
        self.save_btn.clicked.connect(self._save)
        layout.addWidget(self.save_btn)

    def on_queue_changed(self, queue_id: str, role_arn: str, queue_name: str) -> None:
        """Called when Tab 1 queue selection changes."""
        self._role_arn = role_arn
        self._role_name = role_name_from_arn(role_arn)
        self._queue_name = queue_name
        self.queue_label.setText(f"Queue: {queue_name}")
        self.role_label.setText(f"Role: {role_arn or '(none)'}")
        self._refresh()

    def _refresh(self) -> None:
        """Reload ECR repos and current policy."""
        # Load repos
        try:
            self._repos = list_ecr_repos(self._ecr)
        except Exception:
            self._repos = []

        # Load current policy
        policy_doc = get_inline_ecr_policy(self._iam, self._role_name) if self._role_name else None
        self._policy_repo_arns = get_repo_arns_in_policy(policy_doc)
        self._pending_repo_arns = set(self._policy_repo_arns)

        # Update policy text
        if policy_doc:
            self.policy_text.setPlainText(json.dumps(policy_doc, indent=2))
        else:
            self.policy_text.setPlainText("(no DeadlineECRAccess policy found)")

        # Update repo combo with color coding
        self.repo_combo.clear()
        for r in self._repos:
            name = r["repositoryName"]
            arn = r["repositoryArn"]
            in_policy = arn in self._pending_repo_arns
            display = f"{'✓ ' if in_policy else '  '}{name}"
            self.repo_combo.addItem(display, arn)

    def _add_repo(self) -> None:
        """Add the selected repo to the pending policy."""
        idx = self.repo_combo.currentIndex()
        if idx < 0 or idx >= len(self._repos):
            return
        arn = self._repos[idx]["repositoryArn"]
        self._pending_repo_arns.add(arn)
        self._update_preview()

    def _remove_repo(self) -> None:
        """Remove the selected repo from the pending policy."""
        idx = self.repo_combo.currentIndex()
        if idx < 0 or idx >= len(self._repos):
            return
        arn = self._repos[idx]["repositoryArn"]
        self._pending_repo_arns.discard(arn)
        self._update_preview()

    def _update_preview(self) -> None:
        """Update the policy text preview and repo combo indicators."""
        policy_doc = build_ecr_policy(self._pending_repo_arns)
        self.policy_text.setPlainText(json.dumps(policy_doc, indent=2))
        # Refresh combo indicators
        current_idx = self.repo_combo.currentIndex()
        self.repo_combo.blockSignals(True)
        self.repo_combo.clear()
        for r in self._repos:
            name = r["repositoryName"]
            arn = r["repositoryArn"]
            in_policy = arn in self._pending_repo_arns
            display = f"{'✓ ' if in_policy else '  '}{name}"
            self.repo_combo.addItem(display, arn)
        if 0 <= current_idx < self.repo_combo.count():
            self.repo_combo.setCurrentIndex(current_idx)
        self.repo_combo.blockSignals(False)

    def _save(self) -> None:
        """Persist the policy to IAM."""
        if not self._role_name:
            QMessageBox.warning(self, "No Role", "No queue role selected.")
            return
        try:
            save_ecr_policy(self._iam, self._role_name, self._pending_repo_arns)
            self._policy_repo_arns = set(self._pending_repo_arns)
            QMessageBox.information(self, "Saved", f"ECR policy saved to role {self._role_name}.")
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to save policy: {e}")
