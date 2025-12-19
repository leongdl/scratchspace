# VNC Remote Desktop via Deadline Cloud

This setup allows you to access a VNC desktop running on a Deadline Cloud SMF worker from your Mac.

## Architecture

```
┌─────────────┐     SSM Tunnel      ┌─────────────────┐
│    Mac      │ ──────────────────► │  EC2 Proxy      │
│ localhost   │     port 6080       │  Instance       │
│   :6080     │                     │                 │
└─────────────┘                     │  socat proxy    │
                                    │  6688 ◄─► 6080  │
                                    └────────┬────────┘
                                             │
                                    VPC Lattice / Reverse SSH
                                             │
                                    ┌────────▼────────┐
                                    │ Deadline SMF    │
                                    │ Worker          │
                                    │                 │
                                    │ Docker (--host) │
                                    │ noVNC :6080     │
                                    └─────────────────┘
```

## Quick Start

### 1. Setup EC2 Proxy Instance

SSH into your EC2 proxy instance and run:

```bash
# Copy scripts to EC2
scp scripts/ec2-setup.sh scripts/ec2-reverse-proxy.sh ec2-user@<ec2-ip>:~/

# On EC2: Run setup
./ec2-setup.sh

# On EC2: Start the reverse proxy (in a screen/tmux session)
./ec2-reverse-proxy.sh
```

### 2. Configure VPC Lattice (Optional)

If using VPC Lattice instead of direct SSH, follow `scripts/vpc-lattice-setup.md`.

### 3. Submit Deadline Job

```bash
cd job
./submit-vnc.sh
```

Or with custom parameters:

```bash
EC2_PROXY_HOST=10.0.0.65 SESSION_DURATION=7200 ./submit-vnc.sh
```

### 4. Connect from Mac

```bash
./scripts/mac-tunnel.sh
```

Then open: http://localhost:6080/vnc.html

VNC Password: `password`

## Files

### Scripts (`scripts/`)

| File | Description |
|------|-------------|
| `mac-tunnel.sh` | Creates SSM tunnel from Mac to EC2 proxy |
| `ec2-setup.sh` | One-time setup for EC2 proxy instance |
| `ec2-reverse-proxy.sh` | Runs socat to forward 6688→6080 |
| `vpc-lattice-setup.md` | Guide for VPC Lattice configuration |

### Job Bundle (`job/`)

| File | Description |
|------|-------------|
| `template-vnc.yaml` | Deadline job template for VNC desktop |
| `submit-vnc.sh` | Submit script with parameters |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTANCE_ID` | i-0dafdfc660885e366 | EC2 proxy instance ID |
| `INSTANCE_REGION` | us-west-2 | AWS region |
| `EC2_PROXY_HOST` | 10.0.0.65 | EC2 proxy private IP |
| `SESSION_DURATION` | 3600 | VNC session length (seconds) |

### Ports

| Port | Usage |
|------|-------|
| 6080 | noVNC web interface |
| 6688 | VPC Lattice / reverse proxy port |
| 5901 | VNC server (internal) |

## Security Considerations

1. The VNC password is set to `password` - change this in production
2. SSH keys are generated on the worker - pre-configure authorized_keys on EC2
3. Consider using VPC Lattice auth policies for production
4. Limit security group access to known IP ranges

## Troubleshooting

### Can't connect from Mac
- Verify SSM session is active
- Check EC2 proxy is running socat
- Verify security groups allow traffic

### VNC not loading
- Check Deadline job logs for container startup errors
- Verify Docker image was pulled successfully
- Check noVNC is listening on port 6080

### SSH tunnel fails
- Verify SSH key is in EC2's authorized_keys
- Check `GatewayPorts yes` in EC2's sshd_config
- Verify security group allows SSH from worker subnet
