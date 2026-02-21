# Job Bundle

Deadline Cloud job template and submit script for launching a VNC desktop session on an SMF worker.

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | Deadline job template — pulls Docker image, starts VNC, establishes reverse SSH tunnel |
| `submit.sh` | Convenience script to submit the job with default parameters |

## Prerequisites

- Docker image pushed to ECR (see `../docker/README.md`)
- Infrastructure provisioned (see `../scripts/README.md`)
- SSH private key (`vnc_tunnel_key`) placed in this directory — the job attaches it for the reverse tunnel
- VPC Lattice resource config attached to your Deadline fleet

## Submit

```bash
# Default parameters
bash submit.sh

# Custom session duration and proxy
EC2_PROXY_HOST=10.0.0.65 SESSION_DURATION=7200 bash submit.sh
```

## What the Job Does

1. Pulls the Rocky VNC image from ECR
2. Starts the container with `--network host`
3. Waits for noVNC to be ready on port 6080
4. Opens a reverse SSH tunnel through VPC Lattice to the EC2 bastion
5. Monitors the session, auto-restarts the tunnel if it drops
6. Cleans up after the configured duration (default 1 hour)
