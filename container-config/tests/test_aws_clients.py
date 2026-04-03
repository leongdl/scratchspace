"""Tests for aws_clients module — mocked boto3 calls."""

from __future__ import annotations

import json
import os
from unittest.mock import MagicMock, patch

import pytest

from app.aws_clients import (
    _actions_match,
    build_ecr_policy,
    check_role_ecr_access,
    get_inline_ecr_policy,
    get_repo_arns_in_policy,
    list_ecr_repos,
    list_farms,
    list_fleets,
    list_queues,
    load_app_config,
    load_deadline_default_farm,
    role_name_from_arn,
    save_app_config,
)


class TestRoleNameFromArn:
    def test_simple_arn(self) -> None:
        assert role_name_from_arn("arn:aws:iam::123456:role/MyRole") == "MyRole"

    def test_path_arn(self) -> None:
        assert role_name_from_arn("arn:aws:iam::123456:role/service-role/MyRole") == "MyRole"

    def test_empty(self) -> None:
        assert role_name_from_arn("") == ""


class TestListFarms:
    def test_returns_farms(self) -> None:
        mock_client = MagicMock()
        mock_client.list_farms.return_value = {
            "farms": [
                {"farmId": "farm-abc", "displayName": "TestFarm"},
                {"farmId": "farm-def", "displayName": "ProdFarm"},
            ]
        }
        result = list_farms(mock_client)
        assert len(result) == 2
        assert result[0]["farmId"] == "farm-abc"
        assert result[1]["displayName"] == "ProdFarm"

    def test_empty_farms(self) -> None:
        mock_client = MagicMock()
        mock_client.list_farms.return_value = {"farms": []}
        assert list_farms(mock_client) == []


class TestListQueues:
    def test_returns_queues(self) -> None:
        mock_client = MagicMock()
        mock_client.list_queues.return_value = {
            "queues": [{"queueId": "queue-123", "displayName": "MyQueue"}]
        }
        result = list_queues(mock_client, "farm-abc")
        assert len(result) == 1
        mock_client.list_queues.assert_called_once_with(farmId="farm-abc")


class TestListFleets:
    def test_returns_fleets(self) -> None:
        mock_client = MagicMock()
        mock_client.list_fleets.return_value = {
            "fleets": [{"fleetId": "fleet-456", "displayName": "GPUFleet"}]
        }
        result = list_fleets(mock_client, "farm-abc")
        assert len(result) == 1
        mock_client.list_fleets.assert_called_once_with(farmId="farm-abc")


class TestActionsMatch:
    def test_star_wildcard(self) -> None:
        required = {"ecr:GetAuthorizationToken", "ecr:BatchGetImage"}
        assert _actions_match(["*"], required) == required

    def test_service_wildcard(self) -> None:
        required = {"ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"}
        assert _actions_match(["ecr:*"], required) == required

    def test_exact_match(self) -> None:
        required = {"ecr:GetAuthorizationToken", "ecr:BatchGetImage"}
        assert _actions_match(["ecr:GetAuthorizationToken"], required) == {"ecr:GetAuthorizationToken"}

    def test_no_match(self) -> None:
        required = {"ecr:GetAuthorizationToken"}
        assert _actions_match(["s3:GetObject"], required) == set()


class TestCheckRoleEcrAccess:
    def test_managed_policy_with_ecr_name(self) -> None:
        mock_iam = MagicMock()
        mock_iam.list_attached_role_policies.return_value = {
            "AttachedPolicies": [
                {"PolicyArn": "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"}
            ]
        }
        assert check_role_ecr_access(mock_iam, "MyRole") is True

    def test_inline_policy_with_ecr_actions(self) -> None:
        mock_iam = MagicMock()
        mock_iam.list_attached_role_policies.return_value = {"AttachedPolicies": []}
        mock_iam.list_role_policies.return_value = {"PolicyNames": ["ecr-access"]}
        mock_iam.get_role_policy.return_value = {
            "PolicyDocument": {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "ecr:GetAuthorizationToken",
                            "ecr:BatchGetImage",
                            "ecr:GetDownloadUrlForLayer",
                        ],
                        "Resource": "*",
                    }
                ],
            }
        }
        assert check_role_ecr_access(mock_iam, "MyRole") is True

    def test_no_ecr_access(self) -> None:
        mock_iam = MagicMock()
        mock_iam.list_attached_role_policies.return_value = {"AttachedPolicies": []}
        mock_iam.list_role_policies.return_value = {"PolicyNames": []}
        assert check_role_ecr_access(mock_iam, "MyRole") is False

    def test_ecr_star_wildcard_in_inline(self) -> None:
        mock_iam = MagicMock()
        mock_iam.list_attached_role_policies.return_value = {"AttachedPolicies": []}
        mock_iam.list_role_policies.return_value = {"PolicyNames": ["ecr-full"]}
        mock_iam.get_role_policy.return_value = {
            "PolicyDocument": {
                "Version": "2012-10-17",
                "Statement": [
                    {"Effect": "Allow", "Action": "ecr:*", "Resource": "*"}
                ],
            }
        }
        assert check_role_ecr_access(mock_iam, "MyRole") is True

    def test_empty_role_name(self) -> None:
        mock_iam = MagicMock()
        assert check_role_ecr_access(mock_iam, "") is False


class TestBuildEcrPolicy:
    def test_empty_repos(self) -> None:
        policy = build_ecr_policy(set())
        assert len(policy["Statement"]) == 1
        assert policy["Statement"][0]["Sid"] == "ECRAuth"

    def test_with_repos(self) -> None:
        arns = {"arn:aws:ecr:us-west-2:123:repository/myrepo"}
        policy = build_ecr_policy(arns)
        assert len(policy["Statement"]) == 2
        assert policy["Statement"][1]["Sid"] == "ECRReadPush"
        assert "arn:aws:ecr:us-west-2:123:repository/myrepo" in policy["Statement"][1]["Resource"]


class TestGetRepoArnsInPolicy:
    def test_extracts_arns(self) -> None:
        policy = {
            "Statement": [
                {"Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"},
                {
                    "Effect": "Allow",
                    "Action": ["ecr:BatchGetImage"],
                    "Resource": ["arn:aws:ecr:us-west-2:123:repository/repo1"],
                },
            ]
        }
        arns = get_repo_arns_in_policy(policy)
        assert arns == {"arn:aws:ecr:us-west-2:123:repository/repo1"}

    def test_none_policy(self) -> None:
        assert get_repo_arns_in_policy(None) == set()


class TestPersistence:
    def test_save_and_load(self, tmp_path: pytest.TempPathFactory) -> None:
        config_path = str(tmp_path / "container-config.json")
        with patch("app.aws_clients.os.path.expanduser", return_value=config_path):
            with patch("app.aws_clients.os.path.exists", return_value=False):
                assert load_app_config() == {}

            save_app_config({"last_farm_id": "farm-test"})

        # Verify file was written
        assert os.path.exists(config_path)
        with open(config_path) as f:
            data = json.load(f)
        assert data["last_farm_id"] == "farm-test"
