"""Boto3 wrappers for Deadline Cloud, IAM, ECR, and STS."""

from __future__ import annotations

import json
import os
from configparser import ConfigParser
from typing import TYPE_CHECKING, Any

import boto3

if TYPE_CHECKING:
    from mypy_boto3_ecr import ECRClient
    from mypy_boto3_iam import IAMClient

POLICY_NAME = "DeadlineECRAccess"

ECR_READ_PUSH_ACTIONS = [
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchCheckLayerAvailability",
    "ecr:PutImage",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
]

ECR_AUTH_ACTIONS = ["ecr:GetAuthorizationToken"]

ECR_CHECK_ACTIONS = [
    "ecr:GetAuthorizationToken",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
]


def get_deadline_client(region: str = "us-west-2") -> Any:
    """Create a Deadline Cloud boto3 client."""
    return boto3.client("deadline", region_name=region)


def get_iam_client() -> "IAMClient":
    """Create an IAM boto3 client."""
    return boto3.client("iam")


def get_ecr_client(region: str = "us-west-2") -> "ECRClient":
    """Create an ECR boto3 client."""
    return boto3.client("ecr", region_name=region)


def load_deadline_default_farm() -> str:
    """Read the default farm ID from the Deadline CLI config."""
    config = ConfigParser()
    config.read(os.path.expanduser("~/.deadline/config"))
    return config.get("defaults", "farm_id", fallback="")


def load_app_config() -> dict[str, str]:
    """Load persisted app selections from ~/.deadline/container-config.json."""
    path = os.path.expanduser("~/.deadline/container-config.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}


def save_app_config(data: dict[str, str]) -> None:
    """Save app selections to ~/.deadline/container-config.json."""
    path = os.path.expanduser("~/.deadline/container-config.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def list_farms(client: Any) -> list[dict[str, str]]:
    """List all farms."""
    resp = client.list_farms()
    return [{"farmId": f["farmId"], "displayName": f["displayName"]} for f in resp.get("farms", [])]


def list_queues(client: Any, farm_id: str) -> list[dict[str, str]]:
    """List queues for a farm."""
    resp = client.list_queues(farmId=farm_id)
    return [{"queueId": q["queueId"], "displayName": q["displayName"]} for q in resp.get("queues", [])]


def list_fleets(client: Any, farm_id: str) -> list[dict[str, str]]:
    """List fleets for a farm."""
    resp = client.list_fleets(farmId=farm_id)
    return [{"fleetId": f["fleetId"], "displayName": f["displayName"]} for f in resp.get("fleets", [])]


def get_queue_role_arn(client: Any, farm_id: str, queue_id: str) -> str:
    """Get the IAM role ARN for a queue."""
    resp = client.get_queue(farmId=farm_id, queueId=queue_id)
    return resp.get("roleArn", "")


def get_fleet_details(client: Any, farm_id: str, fleet_id: str) -> dict[str, Any]:
    """Get fleet details including roleArn and hostConfiguration."""
    resp = client.get_fleet(farmId=farm_id, fleetId=fleet_id)
    return {
        "roleArn": resp.get("roleArn", ""),
        "displayName": resp.get("displayName", ""),
        "hostConfiguration": resp.get("hostConfiguration", {}),
    }


def role_name_from_arn(arn: str) -> str:
    """Extract role name from an IAM role ARN."""
    if not arn:
        return ""
    # arn:aws:iam::123456:role/path/RoleName or arn:aws:iam::123456:role/RoleName
    parts = arn.split("/")
    return parts[-1] if parts else ""


def _actions_match(actions: list[str], required: set[str]) -> set[str]:
    """Check which required actions are satisfied by the given action list."""
    found: set[str] = set()
    for a in actions:
        if a == "*":
            return set(required)  # wildcard matches everything
        if a.endswith(":*"):
            # Service wildcard like ecr:*
            prefix = a.split(":")[0]
            for r in required:
                if r.startswith(prefix + ":"):
                    found.add(r)
        elif a in required:
            found.add(a)
    return found


def check_role_ecr_access(iam_client: "IAMClient", role_name: str) -> bool:
    """Check if a role has ECR read access (managed or inline policies)."""
    if not role_name:
        return False
    required = set(ECR_CHECK_ACTIONS)
    found_actions: set[str] = set()

    # Check managed policies
    try:
        attached = iam_client.list_attached_role_policies(RoleName=role_name)
        for pol in attached.get("AttachedPolicies", []):
            arn = pol["PolicyArn"]
            if "ContainerRegistry" in arn or "ECR" in arn:
                return True
            pv = iam_client.get_policy(PolicyArn=arn)
            version_id = pv["Policy"]["DefaultVersionId"]
            doc = iam_client.get_policy_version(PolicyArn=arn, VersionId=version_id)
            policy_doc = doc["PolicyVersion"]["Document"]
            if isinstance(policy_doc, str):
                policy_doc = json.loads(policy_doc)
            for stmt in policy_doc.get("Statement", []):
                if stmt.get("Effect") != "Allow":
                    continue
                actions = stmt.get("Action", [])
                if isinstance(actions, str):
                    actions = [actions]
                found_actions |= _actions_match(actions, required)
                if required.issubset(found_actions):
                    return True
    except Exception:
        pass

    # Check inline policies
    try:
        inline = iam_client.list_role_policies(RoleName=role_name)
        for pol_name in inline.get("PolicyNames", []):
            doc_resp = iam_client.get_role_policy(RoleName=role_name, PolicyName=pol_name)
            policy_doc = doc_resp["PolicyDocument"]
            if isinstance(policy_doc, str):
                policy_doc = json.loads(policy_doc)
            for stmt in policy_doc.get("Statement", []):
                if stmt.get("Effect") != "Allow":
                    continue
                actions = stmt.get("Action", [])
                if isinstance(actions, str):
                    actions = [actions]
                found_actions |= _actions_match(actions, required)
                if required.issubset(found_actions):
                    return True
    except Exception:
        pass

    return required.issubset(found_actions)


def get_inline_ecr_policy(iam_client: "IAMClient", role_name: str) -> dict[str, Any] | None:
    """Get the DeadlineECRAccess inline policy document, or None."""
    try:
        resp = iam_client.get_role_policy(RoleName=role_name, PolicyName=POLICY_NAME)
        doc = resp["PolicyDocument"]
        if isinstance(doc, str):
            doc = json.loads(doc)
        return doc
    except iam_client.exceptions.NoSuchEntityException:
        return None
    except Exception:
        return None


def list_ecr_repos(ecr_client: "ECRClient") -> list[dict[str, str]]:
    """List ECR repositories returning name and ARN."""
    repos: list[dict[str, str]] = []
    paginator = ecr_client.get_paginator("describe_repositories")
    for page in paginator.paginate():
        for r in page.get("repositories", []):
            repos.append({"repositoryName": r["repositoryName"], "repositoryArn": r["repositoryArn"]})
    return repos


def get_repo_arns_in_policy(policy_doc: dict[str, Any] | None) -> set[str]:
    """Extract ECR repo ARNs from a policy document."""
    if not policy_doc:
        return set()
    arns: set[str] = set()
    for stmt in policy_doc.get("Statement", []):
        if stmt.get("Effect") != "Allow":
            continue
        resources = stmt.get("Resource", [])
        if isinstance(resources, str):
            resources = [resources]
        for r in resources:
            if ":repository/" in r:
                arns.add(r)
    return arns


def build_ecr_policy(repo_arns: set[str]) -> dict[str, Any]:
    """Build the DeadlineECRAccess policy document for the given repo ARNs."""
    statements: list[dict[str, Any]] = [
        {
            "Sid": "ECRAuth",
            "Effect": "Allow",
            "Action": ECR_AUTH_ACTIONS,
            "Resource": "*",
        },
    ]
    if repo_arns:
        statements.append(
            {
                "Sid": "ECRReadPush",
                "Effect": "Allow",
                "Action": ECR_READ_PUSH_ACTIONS,
                "Resource": sorted(repo_arns),
            }
        )
    return {"Version": "2012-10-17", "Statement": statements}


def save_ecr_policy(iam_client: "IAMClient", role_name: str, repo_arns: set[str]) -> None:
    """Save the DeadlineECRAccess inline policy to the role."""
    policy_doc = build_ecr_policy(repo_arns)
    iam_client.put_role_policy(
        RoleName=role_name,
        PolicyName=POLICY_NAME,
        PolicyDocument=json.dumps(policy_doc),
    )


def update_fleet_host_config(client: Any, farm_id: str, fleet_id: str, script_body: str) -> None:
    """Update a fleet's host configuration script."""
    client.update_fleet(
        farmId=farm_id,
        fleetId=fleet_id,
        hostConfiguration={"scriptBody": script_body, "scriptTimeoutSeconds": 600},
    )
