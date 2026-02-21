# Architecture — Remote VNC Desktop on Deadline Cloud SMF

## Overview

This system provides browser-based access to a GPU-accelerated Linux desktop running on Deadline Cloud Service-Managed Fleet (SMF) workers. The challenge is that SMF workers are fully managed by AWS with no inbound network access. All connectivity must be initiated outbound from the worker.

## Components

```
┌─────────────┐      ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────────┐
│   Your Mac  │      │  EC2 Bastion     │      │  VPC Lattice     │      │  Deadline SMF Worker │
│             │      │  (T3.micro)      │      │                  │      │                      │
│  Browser    │      │                  │      │  Resource        │      │  Docker Container    │
│  localhost  │─SSM─▶│  sshd listening  │◀─────│  Gateway +       │◀─SSH─│  Rocky Linux 9       │
│  :6080      │      │  GatewayPorts=yes│      │  Config (port 22)│      │  XFCE + noVNC :6080  │
└─────────────┘      └──────────────────┘      └──────────────────┘      └──────────────────────┘
```

## Network Flow

There are two tunnels chained together. Neither requires inbound access to the worker.

### Tunnel 1: Worker → EC2 (Reverse SSH)

The Deadline job starts a Docker container with `--network host`, then opens a reverse SSH tunnel:

```
ssh -R 6080:localhost:6080 -N ssm-user@<vpc-lattice-endpoint>
```

- The worker initiates the connection outbound through VPC Lattice
- VPC Lattice routes it to the EC2 bastion's private IP on port 22
- The `-R 6080:localhost:6080` flag tells the EC2's sshd to listen on port 6080 and forward traffic back through the tunnel to the worker's port 6080 (noVNC)
- `GatewayPorts yes` in sshd_config makes the listener bind on `0.0.0.0:6080` instead of `127.0.0.1:6080`

### Tunnel 2: Mac → EC2 (SSM Port Forward)

From your Mac:

```
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'
```

- SSM creates an encrypted tunnel from your Mac to the EC2 instance
- `localhost:6080` on your Mac maps to port 6080 on the EC2
- Which is the reverse tunnel listener, forwarding to the worker's noVNC

### End-to-End Path

```
Browser → localhost:6080 → SSM tunnel → EC2:6080 → reverse SSH tunnel → Worker:6080 (noVNC)
```

All traffic stays within AWS private networking. No public IPs, no internet exposure.

## VPC Lattice

VPC Lattice provides the private network path from SMF workers to the EC2 bastion. It consists of three resources:

### Resource Gateway

Creates ENIs in your VPC subnet. This is where VPC Lattice traffic enters your VPC.

```
Resource Gateway (ENIs in your subnet)
    ↓
Routes to EC2 private IP
```

### Resource Configuration

Defines the target: your EC2's private IP and port 22 (SSH). Workers access it via a private DNS name:

```
<rcfg-id>.resource-endpoints.deadline.<region>.amazonaws.com
```

This DNS name is only resolvable from SMF workers that have the resource config attached to their fleet. It is not resolvable from the internet or your workstation.

### RAM Share

AWS Resource Access Manager shares the resource configuration with the Deadline Cloud service principal (`fleets.deadline.amazonaws.com`). This authorizes Deadline to attach the resource config to your fleet.

### Directionality

VPC Lattice resource endpoints are unidirectional: workers can initiate connections TO your VPC, but your VPC cannot initiate connections TO workers. This is why we use a reverse SSH tunnel — the worker initiates the connection, then traffic flows both ways over the established tunnel.

## EC2 Bastion

A minimal T3.micro instance. Its only job is to run sshd with `GatewayPorts yes`. No application software, no Docker, no socat.

### User Data (runs at first boot)

- Enables `GatewayPorts yes` in `/etc/ssh/sshd_config`
- Prepares `/home/ssm-user/.ssh/authorized_keys` for the worker's tunnel key
- Restarts sshd

### Security Group

Inbound rules allow traffic only from:
- VPC CIDR (for direct testing)
- VPC Lattice managed prefix list (for SMF worker traffic)

On ports: 22 (SSH tunnel), 6080 (VNC), 8188 (ComfyUI — for future use).

## SMF Worker

Deadline Cloud manages the worker lifecycle. We configure it through:

### Host Configuration (`host_config.sh`)

Runs on each worker at boot. Installs Docker and the NVIDIA container toolkit so the worker can run GPU containers. Key detail: uses `--runtime=nvidia` instead of `--gpus all` to work around a BPF device filter bug in NVIDIA driver 580.x.

### Job Template (`template.yaml`)

The Deadline job does the following in sequence:

1. Cleans up any orphaned containers from previous runs
2. Copies the SSH private key from the job attachment
3. Logs into ECR and pulls the Docker image
4. Starts the container with `--network host`
5. Polls `curl localhost:6080` until noVNC is ready
6. Opens the reverse SSH tunnel to the EC2 bastion via VPC Lattice
7. Monitors the session in a loop:
   - Checks if the container is still running
   - Checks if the SSH tunnel is alive, restarts it if not
   - Logs status every 60 seconds
8. After the configured duration, stops the container and kills the tunnel

### Docker Container

Rocky Linux 9 based on `nvidia/cuda:12.4.0-runtime-rockylinux9`:
- XFCE desktop environment (lightweight, performs well over VNC)
- TigerVNC server on display :1 (port 5901)
- websockify + noVNC on port 6080 (browser-based VNC client)
- NVIDIA CUDA runtime for GPU workloads

## Authentication

### SSH Tunnel Key

A dedicated key pair is used for the reverse tunnel. The private key is attached to the Deadline job as a file parameter. The public key must be added to `/home/ssm-user/.ssh/authorized_keys` on the EC2 bastion.

Multiple users can each generate their own key pair and add their public keys to the same `authorized_keys` file — one key per line. Each user submits jobs with their own private key as the attachment. The bastion accepts all registered keys.

```
# /home/ssm-user/.ssh/authorized_keys
ssh-ed25519 AAAAC3... alice-workstation-key
ssh-ed25519 AAAAC3... bob-workstation-key
ssh-ed25519 AAAAC3... ci-pipeline-key
```

For tunnel-only use, a shared `ssm-user` account with multiple keys is sufficient. No shell access is needed — the SSH connection uses `-N` (no command execution).

### VNC Password

Set to `password` in the Docker image via `vncpasswd`. Change this for production use.

### SSM Access

The Mac connects to the EC2 via SSM Session Manager, which uses IAM authentication. No SSH keys or open ports needed on the Mac side.

## Port Map

| Port | Where | Service |
|------|-------|---------|
| 5901 | Worker container | TigerVNC server (internal only) |
| 6080 | Worker container → EC2 → Mac | noVNC web interface |
| 22   | EC2 bastion | sshd (reverse tunnel endpoint) |
| 8188 | Reserved | ComfyUI (future use) |

## Failure Modes

## Multi-Worker Scaling

A single EC2 bastion can serve multiple workers simultaneously. Each worker opens its own reverse SSH tunnel on a unique port — sshd handles them independently.

```
Worker 1:  ssh -R 6080:localhost:6080 ssm-user@<endpoint>   →  Mac forwards port 6080
Worker 2:  ssh -R 6081:localhost:6080 ssm-user@<endpoint>   →  Mac forwards port 6081
Worker 3:  ssh -R 8188:localhost:8188 ssm-user@<endpoint>   →  Mac forwards port 8188
```

SSH is lightweight — a t3.micro can comfortably handle dozens of concurrent tunnels. The constraints are:

1. Port allocation — each worker needs a unique remote port on the bastion. Pass it as a job parameter (e.g. `TUNNEL_PORT`).
2. Security group — the port range must be allowed inbound. Use a range like 6080-6099 instead of individual rules.
3. Mac-side tunnels — each session needs its own SSM port forward matching the assigned port.

No changes to VPC Lattice are needed — all workers connect to the same endpoint on port 22. The port differentiation happens at the SSH `-R` level, not at the network layer.

## Failure Modes

| Failure | Impact | Recovery |
|---------|--------|----------|
| SSH tunnel drops | Mac can't reach VNC | Job auto-restarts the tunnel |
| Container crashes | VNC unavailable | Job detects and exits; resubmit |
| EC2 bastion reboots | Both tunnels break | SSM reconnects; job restarts SSH tunnel |
| VPC Lattice endpoint unreachable | Worker can't establish tunnel | Check RAM share status and fleet config |
| SSM session times out | Mac disconnected | Re-run the SSM port forward command |
