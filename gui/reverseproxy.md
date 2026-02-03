# Reverse SSH Proxy Setup for Deadline Cloud GUI Access

## Overview

This EC2 instance (10.0.0.65) acts as a reverse proxy to allow access to GUI applications running on Deadline Cloud workers.

## How It Works

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Deadline Worker │     │   VPC Lattice    │     │  EC2 Proxy       │     │    Your Mac      │
│  (Container)     │     │   Endpoint       │     │  (10.0.0.65)     │     │                  │
├──────────────────┤     ├──────────────────┤     ├──────────────────┤     ├──────────────────┤
│                  │     │                  │     │                  │     │                  │
│  App (ComfyUI/   │     │  rcfg-011bc...   │     │                  │     │  Browser         │
│  VNC) :PORT      │────▶│  .resource-      │────▶│  :PORT           │◀────│  localhost:PORT  │
│                  │ SSH │  endpoints...    │     │  (listening)     │ SSM │                  │
│  (localhost)     │ -R  │                  │     │                  │     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Step 1: Worker → EC2 (Reverse SSH Tunnel)

The Deadline job runs an SSH command with `-R` (reverse tunnel):

```bash
ssh -i ~/.ssh/tunnel_key \
    -R PORT:localhost:PORT \
    -N \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    ssm-user@rcfg-011bc61e9efbfbd1e.resource-endpoints.deadline.us-west-2.amazonaws.com
```

This creates a listener on EC2:PORT that forwards traffic back to Worker:PORT.

### Step 2: Mac → EC2 (SSM Port Forward)

From your Mac:

```bash
aws ssm start-session \
    --target i-XXXXXXXXX \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["PORT"],"localPortNumber":["PORT"]}' \
    --region us-west-2
```

## EC2 Proxy Configuration

### Required: GatewayPorts

The EC2 instance must have `GatewayPorts yes` in `/etc/ssh/sshd_config`:

```bash
# Check current setting
sudo grep -i gatewayports /etc/ssh/sshd_config

# Enable if not set
sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

This allows the reverse tunnel to bind to `0.0.0.0:PORT` instead of just `127.0.0.1:PORT`.

### SSH Key Setup

The worker's public key must be in `~/.ssh/authorized_keys` on this EC2 instance.

Current authorized keys location: `/home/ssm-user/.ssh/authorized_keys`

## Port Assignments

| Application | Port |
|-------------|------|
| ComfyUI     | 8188 |
| VNC/noVNC   | 6080 |

## Troubleshooting

### Port not listening on EC2

The reverse tunnel only exists while the job is running. Check:

```bash
ss -tlnp | grep PORT
```

If empty, the job may have stopped or the SSH tunnel failed.

### Connection refused

1. Verify job is running in Deadline console
2. Check worker logs for SSH tunnel errors
3. Ensure GatewayPorts is enabled
4. Verify SSH key is authorized

### VPC Lattice endpoint

The endpoint `rcfg-011bc61e9efbfbd1e.resource-endpoints.deadline.us-west-2.amazonaws.com` routes traffic from the Deadline worker VPC to this EC2 instance.
