# ComfyUI GUI Demo via SSM — Design

## Overview

A Deadline Cloud job bundle that combines the SSM managed node pattern with the ComfyUI container pattern. Instead of batch-rendering a workflow, this job starts ComfyUI in interactive GUI mode and exposes it to the user via SSM Session Manager port forwarding.

## Architecture

```
┌──────────────────────┐       ┌──────────────────────────────────────┐
│  Submitter (you)     │       │  Deadline Cloud Worker (GPU)         │
│                      │       │                                      │
│  1. aws ssm          │       │  3. ECR login + docker pull          │
│     create-activation│       │  4. docker run comfyui container     │
│                      │──────▶│  5. Wait for localhost:8188 ready    │
│  2. deadline submit  │ params│  6. ssm-setup-cli -register          │
│     --parameters     │       │  7. Print mi-XXXXXXX + connect cmd  │
│     ActivationCode=X │       │  8. Sleep SESSION_MINUTES            │
│     ActivationId=Y   │       │  9. Deregister + docker stop         │
│     SessionMinutes=60│       │                                      │
└──────────────────────┘       └──────────────────────────────────────┘
         │
         │  After job starts, user connects:
         │
         │  aws ssm start-session --target mi-XXXXXXX \
         │    --document-name AWS-StartPortForwardingSession \
         │    --parameters '{"portNumber":["8188"],"localPortNumber":["8188"]}'
         │
         │  Then open http://localhost:8188 in browser
         ▼
```

## Job Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ActivationCode` | STRING | *(required)* | SSM hybrid activation code |
| `ActivationId` | STRING | *(required)* | SSM hybrid activation ID |
| `AWS_REGION` | STRING | us-west-2 | Region for SSM + ECR |
| `SessionMinutes` | INT | 120 | How long to keep the session alive |
| `ECR_REGISTRY` | STRING | *(auto-detected)* | ECR registry URL |
| `COMFYUI_REPOSITORY` | STRING | comfyui | ECR repository name |
| `COMFYUI_TAG` | STRING | latest | Docker image tag |
| `COMFYUI_PORT` | INT | 8188 | Port ComfyUI listens on |

## Job Script Flow

1. ECR login + smart pull (skip if local digest matches remote)
2. `docker run` the ComfyUI container with `--network host` and GPU passthrough
3. Poll `curl localhost:8188` until ComfyUI is ready (up to 360s)
4. Download `ssm-setup-cli`, register as managed node
5. Print the `mi-*` ID and the exact `aws ssm start-session` port-forwarding command
6. Loop for `SessionMinutes`, printing status + GPU stats every 60s
7. On exit: deregister SSM node, stop + remove container

## Prerequisites

- Same as ssh_ssm_managed_node: SSMServiceRole, advanced-instances tier, sudo for job-user
- Same as comfy-demo: Docker + NVIDIA Container Toolkit on worker, ECR pull access
- ComfyUI container image pushed to ECR

## File Structure

```
comfy-gui-demo/
├── design.md              ← this file
├── README.md              ← usage guide
├── submit.sh              ← creates SSM activation + submits job
├── setup/
│   └── host_config.sh     ← worker host setup (docker + nvidia + sudo)
└── job/
    └── template.yaml      ← Deadline Cloud job template
```
