# gui-demo — Remote GPU Desktop on Deadline Cloud

Run a GPU-accelerated Rocky Linux desktop on Deadline Cloud Service-Managed Fleet workers. Two remote display options are available:

- **Amazon DCV** (`Dockerfile.rocky-nice-dcv-gnome`) — MATE desktop + VirtualGL + DCV 2025.0, GPU-accelerated, browser or native client on port 8443 **(active)**
- **VNC** (`Dockerfile.rocky`) — TigerVNC + noVNC, lightweight, browser-based on port 6080

## Local Testing

### Amazon DCV (MATE + VirtualGL — active image)

```bash
cd docker
docker build -t desktop-demo-dcv:latest -f Dockerfile.rocky-nice-dcv-gnome .

docker run -d \
  --runtime=nvidia --gpus all \
  --network host \
  --cap-add SYS_PTRACE \
  --device /dev/dri:/dev/dri \
  --name rocky-dcv \
  desktop-demo-dcv:latest

# Connect via browser: https://localhost:8443
# Credentials: rockyuser / rocky

docker stop rocky-dcv && docker rm rocky-dcv
```

### VNC (noVNC in browser)

```bash
cd docker
docker build -t rocky-vnc:latest -f Dockerfile.rocky .

docker run -d \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  --network host \
  --name rocky-vnc \
  rocky-vnc:latest

# Open in browser: http://localhost:6080/vnc.html  (password: password)

docker stop rocky-vnc && docker rm rocky-vnc
```

#### DCV License (required for EC2)

DCV is free on EC2 but the instance IAM role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::dcv-license.<region>/*"
    }
  ]
}
```

## Quick Start

```bash
# 1. Generate the SSH tunnel key pair
bash generate_tunnel_key.sh

# 2. Provision EC2 proxy + VPC Lattice (if not already done)
python3 scripts/setup_infrastructure.py --create

# 3. Register your public key on the EC2 bastion
source creds.sh
PUB_KEY=$(cat job/vnc_tunnel_key.pub)
aws ssm send-command --instance-ids i-0227d51eeadb27c64 --region us-west-2 \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"id ssm-user 2>/dev/null || useradd -m ssm-user\",\"mkdir -p /home/ssm-user/.ssh\",\"echo '$PUB_KEY' >> /home/ssm-user/.ssh/authorized_keys\",\"chmod 700 /home/ssm-user/.ssh\",\"chmod 600 /home/ssm-user/.ssh/authorized_keys\",\"chown -R ssm-user:ssm-user /home/ssm-user/.ssh\"]"

# 4. Attach VPC Lattice resource config to your Deadline fleet (console)
#    ARN: arn:aws:vpc-lattice:us-west-2:257639634185:resourceconfiguration/rcfg-0a8ab60ee0c8594b6

# 5. Submit the job
cd job
bash submit.sh

# 6. Connect from Mac
aws ssm start-session --target i-0227d51eeadb27c64 --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8443"],"localPortNumber":["8443"]}'

# 7. Open https://localhost:8443 — credentials: rockyuser / rocky
```

## Structure

```
gui-demo/
├── README.md                          # This file
├── ARCHITECTURE.md                    # End-to-end technical design
├── FARM_SETUP.md                      # Farm, fleet, queue, and infra state
├── .gitignore                         # Excludes keys, pems, resources.json
├── generate_tunnel_key.sh             # Creates SSH key pair for the reverse tunnel
├── docker/
│   ├── Dockerfile.rocky-nice-dcv-gnome  # MATE + VirtualGL + DCV 2025.0 (active)
│   ├── Dockerfile.rocky-nice-dcv        # XFCE + DCV 2025.0
│   ├── Dockerfile.rocky                 # XFCE + noVNC (VNC fallback)
│   ├── start-dcv-gnome.sh               # Entrypoint for MATE/DCV container
│   ├── start-dcv.sh                     # Entrypoint for XFCE/DCV container
│   ├── start.sh                         # Entrypoint for VNC container
│   ├── README.md                        # VNC container docs
│   └── README-nice-dcv.md               # DCV container docs (host setup, comparison)
├── job/
│   ├── template.yaml                  # Deadline job template (DCV, port 8443)
│   ├── submit.sh                      # Job submission script
│   └── README.md
├── scripts/
│   ├── setup_infrastructure.py        # One-shot infra provisioning
│   ├── host_config.sh                 # SMF worker host configuration
│   └── README.md
└── resources.json                     # Generated — resource IDs/ARNs
```

## See Also

- `ARCHITECTURE.md` — networking, tunnels, and VPC Lattice design
- `FARM_SETUP.md` — farm, fleet, queue, IAM roles, and VPC Lattice state
- `docker/README-nice-dcv.md` — DCV container docs, host GPU setup, DCV vs VNC comparison
- `job/README.md` — job template and submission

## FAQ

**Job fails with `cp: cannot stat ... assetroot-...: No such file or directory`**

The SSH tunnel key (`vnc_tunnel_key`) is missing. Generate it:
```bash
bash generate_tunnel_key.sh
```
Then register the public key on the EC2 bastion (see step 3 in Quick Start).

**Job fails with `manifest for .../desktop-demo-dcv:latest not found`**

The Docker image hasn't been pushed to ECR. Build and push:
```bash
source creds.sh
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 257639634185.dkr.ecr.us-west-2.amazonaws.com
cd docker
docker build -t desktop-demo-dcv:latest -f Dockerfile.rocky-nice-dcv-gnome .
docker tag desktop-demo-dcv:latest 257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo-dcv:latest
docker push 257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo-dcv:latest
```

**SSM tunnel connects but browser shows nothing**

The job may still be starting — the worker needs to pull the image, start the container, wait for DCV, then open the tunnel. This can take a few minutes on first run. Check job logs in the Deadline console.

## Adding Your Workstation Key

Each user needs their own SSH key pair. Generate one and register the public key:

```bash
# 1. Generate your key (run from gui-demo/)
bash generate_tunnel_key.sh

# 2. Register on the bastion via SSM
source creds.sh
PUB_KEY=$(cat job/vnc_tunnel_key.pub)
aws ssm send-command --instance-ids i-0227d51eeadb27c64 --region us-west-2 \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"echo '$PUB_KEY' >> /home/ssm-user/.ssh/authorized_keys\"]"
```

Multiple users can each add their own key — one per line in `authorized_keys`. No restart needed.
