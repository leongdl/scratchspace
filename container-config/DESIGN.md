# Container Config — Deadline Cloud Docker Setup Tool

## Overview

A PySide6 desktop application that configures Deadline Cloud farms, queues, and fleets for Docker/ECR container workloads. It provides a visual way to check and fix IAM permissions, ECR access, and fleet host configuration — replacing the manual steps in `demo/deadline-setup.md`.

## Architecture

```
container-config/
├── DESIGN.md
├── requirements.txt
└── app/
    ├── __init__.py
    ├── main.py              ← Entry point, QTabWidget with 3 tabs
    ├── aws_clients.py       ← Boto3 wrappers (deadline, iam, ecr, sts)
    ├── tab_summary.py       ← Tab 1: Farm/Queue/Fleet overview
    ├── tab_queue_config.py  ← Tab 2: Queue IAM + ECR management
    └── tab_fleet_config.py  ← Tab 3: Fleet host config builder
```

## Dependencies

- Python 3.10+
- PySide6
- boto3
- deadline (CLI, for reading default farm config)

## Tab 1: Summary

### Layout

```
┌─────────────────────────────────────────────────┐
│  Farm:   [ ▼ farm dropdown                    ] │
│  Queue:  [ ▼ queue dropdown ] [🟢 ECR Access]   │
│  Fleet:  [ ▼ fleet dropdown ] [🟢 IAM] [🟢 Docker] │
└─────────────────────────────────────────────────┘
```

### Behavior

- Farm dropdown: populated from `deadline list-farms`. Pre-selects the default farm from `deadline config get defaults.farmId`.
- Queue dropdown: populated from `deadline list-queues --farmId <selected>`. On selection change, checks the queue's IAM role for ECR permissions.
  - 🟢 Green indicator: queue role has `ecr:GetAuthorizationToken` + `ecr:BatchGetImage` + `ecr:GetDownloadUrlForLayer`
  - 🔴 Red indicator: missing ECR permissions
- Fleet dropdown: populated from `deadline list-fleets --farmId <selected>`. On selection change:
  - IAM indicator: 🟢 if fleet role has ECR permissions, 🟡 yellow if not
  - Docker indicator: 🟢 if fleet's `hostConfiguration` script contains `docker` install commands, 🔴 if not

### AWS API Calls

- `deadline list-farms` → farm list
- `deadline list-queues --farmId` → queue list
- `deadline list-fleets --farmId` → fleet list
- `deadline get-queue --farmId --queueId` → `roleArn`
- `deadline get-fleet --farmId --fleetId` → `roleArn`, `configuration.customerManaged.workerCapabilities` or host config
- `iam list-attached-role-policies --role-name` → check for ECR policies
- `iam list-role-policies --role-name` → check inline policies for ECR actions

### ECR Permission Check Logic

For a role to have ECR access, it needs at minimum:
1. `ecr:GetAuthorizationToken` (on `*`)
2. `ecr:BatchGetImage` (on specific repo or `*`)
3. `ecr:GetDownloadUrlForLayer` (on specific repo or `*`)

Check both managed policies (via `get-policy` + `get-policy-version`) and inline policies (via `get-role-policy`).

## Tab 2: Queue Config

### Layout

```
┌─────────────────────────────────────────────────┐
│  Queue: <name from Tab 1>                       │
│  Role:  arn:aws:iam::xxx:role/QueueRole         │
│                                                 │
│  ECR Repositories:                              │
│  [ ▼ repo dropdown (green=in policy, black=not)]│
│  [ Add to Policy ] [ Remove from Policy ]       │
│                                                 │
│  Current IAM Policy:                            │
│  ┌─────────────────────────────────────────┐    │
│  │ {                                (read  │    │
│  │   "Version": "2012-10-17",       only)  │    │
│  │   "Statement": [...]                    │    │
│  │ }                                       │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  [ Save ]                                       │
└─────────────────────────────────────────────────┘
```

### Behavior

- Displays the queue name and role ARN from Tab 1 selection
- ECR repo dropdown: populated from `ecr describe-repositories`. Each repo is colored:
  - Green text: repo ARN appears in the role's policy
  - Black text: repo not in policy
- "Add to Policy": creates/updates an inline policy `DeadlineECRAccess` on the queue role granting `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload` for the selected repo
- "Remove from Policy": removes the selected repo ARN from the inline policy
- Policy text box: read-only, shows the current effective inline policy JSON (refreshed after add/remove)
- Save button: calls `iam put-role-policy` to persist the constructed policy

### ECR Actions Granted

For read + push access:
```json
{
  "ecr:GetAuthorizationToken",
  "ecr:BatchGetImage",
  "ecr:GetDownloadUrlForLayer",
  "ecr:BatchCheckLayerAvailability",
  "ecr:PutImage",
  "ecr:InitiateLayerUpload",
  "ecr:UploadLayerPart",
  "ecr:CompleteLayerUpload"
}
```

`GetAuthorizationToken` is on `Resource: "*"`, the rest are scoped to the specific repo ARN.

## Tab 3: Fleet Config

### Layout

```
┌─────────────────────────────────────────────────┐
│  Fleet: <name from Tab 1>                       │
│                                                 │
│  Host Configuration Options:                    │
│  [✓] Install Docker                             │
│  [✓] Job-user passwordless sudo                 │
│  [ ] NVIDIA Container Toolkit                   │
│  [ ] Swap  [ ▼ 32GB | 64GB | 96GB | 128GB ]    │
│                                                 │
│  Generated Host Config Script:                  │
│  ┌─────────────────────────────────────────┐    │
│  │ #!/bin/bash                      (read  │    │
│  │ set -e                           only)  │    │
│  │ # Install Docker                 Arial  │    │
│  │ dnf install -y docker            font)  │    │
│  │ ...                                     │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  [ Save ]                                       │
└─────────────────────────────────────────────────┘
```

### Behavior

- Displays the fleet name from Tab 1 selection
- Checkboxes toggle sections of the host config script:
  - **Install Docker**: `dnf install -y docker`, `systemctl enable/start docker`, `usermod -aG docker job-user`
  - **Job-user passwordless sudo**: `echo "job-user ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/job-user`
  - **NVIDIA Container Toolkit**: install nvidia-container-toolkit repo, install package, `nvidia-ctk runtime configure`, generate CDI spec, restart docker
  - **Swap**: checkbox to enable, plus a dropdown for size: 32GB, 64GB, 96GB, 128GB. `fallocate -l <size>G /swapfile`, mkswap, swapon, fstab entry
- Text box: read-only, monospace Arial font, shows the combined script based on checked options. Updates live as checkboxes change.
- On load: parses the fleet's existing host config (from `get-fleet` API) and pre-checks the matching checkboxes
- Save button: calls `update-fleet` to set the new host configuration script

### Script Generation

Each checkbox maps to a script fragment (sourced from the patterns in `comfy-demo/setup/host_config.sh`). Fragments are concatenated with a `#!/bin/bash\nset -e\n` header.

### AWS API Calls

- `deadline get-fleet --farmId --fleetId` → current host config script
- `deadline update-fleet --farmId --fleetId --configuration` → save new host config

## Boto3 API Reference

The service name is `deadline` (not `deadline-cloud`). Create the client with:
```python
client = boto3.client("deadline", region_name="us-west-2")
```

### Key Methods

| Method | Parameters | Returns |
|--------|-----------|---------|
| `list_farms()` | — | `{"farms": [{"farmId", "displayName", ...}]}` |
| `list_queues(farmId=)` | farmId | `{"queues": [{"queueId", "displayName", ...}]}` |
| `list_fleets(farmId=)` | farmId | `{"fleets": [{"fleetId", "displayName", ...}]}` |
| `get_queue(farmId=, queueId=)` | farmId, queueId | `{"roleArn", "displayName", ...}` |
| `get_fleet(farmId=, fleetId=)` | farmId, fleetId | `{"roleArn", "displayName", "hostConfiguration": {"scriptBody", "scriptTimeoutSeconds"}, ...}` |
| `update_fleet(farmId=, fleetId=, hostConfiguration=)` | farmId, fleetId, hostConfiguration={"scriptBody": str, "scriptTimeoutSeconds": int} | — |

### Deadline CLI Default Config

The Deadline CLI stores defaults in `~/.deadline/config` (INI format). Read with:
```python
from configparser import ConfigParser
config = ConfigParser()
config.read(os.path.expanduser("~/.deadline/config"))
default_farm = config.get("defaults", "farm_id", fallback="")
```

## Persistence

The app persists user selections to `~/.deadline/container-config.json`:

```json
{
  "last_farm_id": "farm-xxx",
  "last_queue_id": "queue-xxx",
  "last_fleet_id": "fleet-xxx",
  "region": "us-west-2"
}
```

### Load Order (Farm Selection)

1. Read `~/.deadline/container-config.json` → `last_farm_id`
2. If not found, read `~/.deadline/config` → `defaults.farm_id`
3. If not found, select the first farm from `list_farms()`

### Load Order (Queue/Fleet Selection)

1. Read `~/.deadline/container-config.json` → `last_queue_id` / `last_fleet_id`
2. If the saved ID belongs to the currently selected farm, pre-select it
3. Otherwise, select the first item in the list

### Save Trigger

Selections are saved to `container-config.json` whenever the user changes a dropdown in Tab 1.

Tab 1 selections drive Tabs 2 and 3:
- When queue selection changes in Tab 1 → Tab 2 refreshes with new queue's role/policy
- When fleet selection changes in Tab 1 → Tab 3 refreshes with new fleet's host config
- Use Qt signals/slots: Tab 1 emits `queue_changed(queue_id, role_arn)` and `fleet_changed(fleet_id)`

## Error Handling

- All AWS API calls wrapped in try/except with status bar messages
- If credentials are missing/expired, show a dialog prompting the user to configure AWS credentials
- Network errors show a retry option in the status bar
- IAM permission errors (AccessDenied) show a clear message about which permission is needed

## Threading

- All AWS API calls run in `QThread` workers to keep the UI responsive
- Loading indicators shown while API calls are in flight
- Results delivered back to the main thread via signals
