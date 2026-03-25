# ComfyUI GUI Demo — Interactive Session on Deadline Cloud via SSM

Run ComfyUI interactively on a Deadline Cloud GPU worker and access the web UI from your laptop through SSM Session Manager port forwarding. No SSH keys, no public IPs, no reverse tunnels — just a single `aws ssm start-session` command.

The idea: design your workflow interactively in the ComfyUI GUI, then export the API-format JSON and submit it as a headless batch render using the companion demos ([comfy-demo](../comfy-demo/), [comfy-demo2](../comfy-demo2/), [comfy-demo3](../comfy-demo3/)). Those demos take a workflow JSON + input files, spin up the same container, submit the workflow via the ComfyUI API, poll for completion, and collect the output — all unattended.

## How SSM Access Works

When you submit the job, the submit script first creates a one-time SSM hybrid activation token via `aws ssm create-activation`. The Deadline Cloud job starts on a GPU worker, pulls the ComfyUI container from ECR, and launches it with `--network host` so ComfyUI listens on `localhost:8188` on the worker. Once ComfyUI is responding, the job downloads `ssm-setup-cli` and registers the worker as an SSM managed node using the activation token. It prints the `mi-*` node ID and the exact port-forwarding command to the job log. You copy that command, run it locally, and SSM tunnels port 8188 from the worker to your machine — then you just open `http://localhost:8188` in your browser. The session stays alive for the configured duration (default 2 hours), then the job deregisters the SSM node and stops the container.

```
┌─────────────────┐         ┌──────────────────────────────────────┐
│  Your Laptop    │         │  Deadline Cloud GPU Worker           │
│                 │         │                                      │
│  submit.sh ─────┼────────▶│  1. docker pull comfyui from ECR    │
│  (creates SSM   │  params │  2. docker run --network host       │
│   activation +  │         │  3. Wait for localhost:8188 ready   │
│   submits job)  │         │  4. ssm-setup-cli -register         │
│                 │         │  5. Print mi-XXXXXXX to job log     │
│                 │         │  6. Keep alive for N minutes        │
│                 │   SSM   │  7. Cleanup on exit                 │
│  aws ssm ───────┼────────▶│                                      │
│  start-session  │  tunnel │     ┌──────────────────────┐         │
│  --target mi-X  │◀───────▶│     │  ComfyUI Container   │         │
│                 │  :8188  │     │  localhost:8188       │         │
│  Browser:       │         │     │  GPU: L40S / L4       │         │
│  localhost:8188 │         │     └──────────────────────┘         │
└─────────────────┘         └──────────────────────────────────────┘
```

## Related Demos

| Demo | What it does | Container |
|------|-------------|-----------|
| [comfy-gui-demo](.) (this) | Interactive ComfyUI GUI session via SSM | `sqex2:wans2v` |
| [comfy-demo](../comfy-demo/) | Headless Wan 2.2 S2V batch render | `sqex2:wans2v` |
| [comfy-demo2](../comfy-demo2/) | Headless Wan 2.2 S2V batch render (variant) | `sqex2:wans2v` |
| [comfy-demo3](../comfy-demo3/) | Headless Wan 2.2 S2V batch render (variant) | `sqex2:wans2v` |
| [ssh_ssm_managed_node](../ssh_ssm_managed_node/) | SSH shell access to worker via SSM (no container) | N/A |

All demos share the same ComfyUI container image (`224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:wans2v`, ~52GB). The container has Wan 2.2 S2V 14B fp8 + wav2vec2 + LightX2V LoRA baked in. The workflow is: design in the GUI (this demo) → export API JSON → submit headless (comfy-demo*).

## Container Image

The image is already built and pushed to ECR:

```
224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:wans2v
  Pushed:  2026-03-10
  Size:    ~52GB (compressed)
  Base:    Rocky Linux 9 + CUDA 12.6 + PyTorch 2.7.0 + ComfyUI
  Models:  Wan 2.2 S2V 14B fp8, UMT5-XXL fp8, wav2vec2, LightX2V LoRA, Wan 2.1 VAE
```

No need to rebuild — the submit script and job template default to this image.

## Setup

### Prerequisites

- A Deadline Cloud farm with a GPU fleet and queue
  - Fleet instance type: `g6e.xlarge` (L40S 48GB) recommended, `g6.xlarge` (L4 24GB) works with `--lowvram`
  - Root volume: 200GB+ (the container is ~70GB uncompressed)
- AWS CLI v2 with the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) installed locally
- Deadline Cloud CLI (`pip install deadline`)
- IAM permissions: `ssm:CreateActivation` for the submitter

### 1. Host Configuration

Run the host config script on each worker (or set it as the fleet's host configuration command):

```bash
bash comfy-gui-demo/setup/host_config.sh
```

This installs:
- Docker with NVIDIA runtime + CDI spec
- Passwordless sudo for `job-user` (required for SSM agent install)
- 32GB swap file (needed for g6.xlarge with 16GB RAM)

### 2. ECR Access

Both the fleet role and queue role need ECR pull access so workers can pull the container:

```bash
# Queue role
aws iam attach-role-policy \
  --role-name <YOUR_QUEUE_ROLE> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Fleet role
aws iam attach-role-policy \
  --role-name <YOUR_FLEET_ROLE> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### 3. SSM IAM Role (once per account)

Create the IAM role that SSM uses for hybrid managed nodes:

```bash
aws iam create-role --role-name SSMServiceRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ssm.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy --role-name SSMServiceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### 4. Enable Advanced-Instances Tier (once per region)

Session Manager requires the advanced-instances tier for hybrid `mi-*` nodes:

```bash
aws ssm update-service-setting \
  --setting-id "arn:aws:ssm:us-west-2:<ACCOUNT_ID>:servicesetting/ssm/managed-instance/activation-tier" \
  --setting-value "advanced" \
  --region us-west-2
```

Cost: ~$0.00695/hr per managed instance. Negligible for short-lived sessions.

## Usage

### Submit

```bash
cd comfy-gui-demo

# Default: 120 min session, SSMServiceRole, us-west-2
./submit.sh

# Custom duration (4 hours)
./submit.sh 240

# Custom IAM role and region
./submit.sh 120 MySSMRole us-east-1

# Override container image
ECR_REGISTRY=123456789.dkr.ecr.us-west-2.amazonaws.com \
DOCKER_REPO=my-comfyui DOCKER_TAG=latest \
./submit.sh
```

### Connect

Watch the Deadline Cloud job log. Once ComfyUI is ready and SSM is registered, you'll see:

```
ComfyUI is READY on port 8188
SSM Managed Node ID: mi-0abc1234def56789

Connect with port forwarding:

  aws ssm start-session --target mi-0abc1234def56789 --region us-west-2 \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["8188"],"localPortNumber":["8188"]}'
```

Run that command, then open `http://localhost:8188` in your browser.

### Export Workflow for Headless Rendering

1. Design your workflow in the ComfyUI GUI
2. Click "Save (API Format)" to export the workflow as JSON
3. Submit it as a headless batch job using one of the companion demos:

```bash
cd comfy-demo2/job
FARM_ID=farm-xxx QUEUE_ID=queue-xxx \
WORKFLOW=/path/to/my-workflow-api.json \
./submit.sh
```

## File Structure

```
comfy-gui-demo/
├── README.md              ← this file
├── design.md              ← design document
├── submit.sh              ← creates SSM activation + submits job
├── setup/
│   └── host_config.sh     ← worker host setup (docker + nvidia + sudo + swap)
└── job/
    └── template.yaml      ← Deadline Cloud job template
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FARM_ID` | *(hardcoded)* | Deadline Cloud farm ID |
| `QUEUE_ID` | *(hardcoded)* | Deadline Cloud queue ID |
| `ECR_REGISTRY` | `224071664257.dkr.ecr.us-west-2.amazonaws.com` | ECR registry |
| `DOCKER_REPO` | `sqex2` | ECR repository name |
| `DOCKER_TAG` | `wans2v` | Docker image tag |
| `COMFYUI_PORT` | `8188` | ComfyUI port |

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `Nonexistent role or missing ssm service principal` | SSMServiceRole doesn't exist | Run the IAM role creation commands in Setup step 3 |
| `Enable advanced-instances tier` | Standard tier can't use Session Manager with `mi-*` nodes | Run the `update-service-setting` command in Setup step 4 |
| ComfyUI container fails to start | Not enough disk space for the ~70GB image | Ensure 200GB+ root volume on the fleet |
| OOM during inference | GPU VRAM too small | Use g6e.xlarge (L40S 48GB) instead of g6.xlarge (L4 24GB) |
| SSM session disconnects | Session idle timeout | Reconnect with the same `aws ssm start-session` command |
