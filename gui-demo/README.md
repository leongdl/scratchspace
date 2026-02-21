# gui-demo — Remote GPU Desktop on Deadline Cloud

Run a GPU-accelerated Rocky Linux desktop on Deadline Cloud Service-Managed Fleet workers. Two remote display options are available:

- **VNC** (`Dockerfile.rocky`) — TigerVNC + noVNC, lightweight, browser-based on port 6080
- **Amazon DCV** (`Dockerfile.rocky-nice-dcv`) — GPU-accelerated streaming, better quality, browser or native client on port 8443

## Local Testing

### VNC (noVNC in browser)

Build and run the container locally to verify everything works before pushing to ECR and deploying on Deadline Cloud.

```bash
# Build the image
cd docker
docker build -t rocky-vnc:latest -f Dockerfile.rocky .

# Run with GPU access (requires NVIDIA runtime configured on the host)
docker run -d \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  --network host \
  --name rocky-vnc \
  rocky-vnc:latest

# Open in browser
# http://localhost:6080/vnc.html  (password: password)

# Stop when done
docker stop rocky-vnc && docker rm rocky-vnc
```

If the host doesn't have an NVIDIA GPU, drop the runtime flags and run CPU-only:

```bash
docker run -d --network host --name rocky-vnc rocky-vnc:latest
```

### Amazon DCV (browser or native client)

```bash
# Build the image
cd docker
docker build -t rocky-dcv:latest -f Dockerfile.rocky-nice-dcv .

# Run with GPU access
docker run -d \
  --runtime=nvidia --gpus all \
  --network host \
  --name rocky-dcv \
  rocky-dcv:latest

# Connect via browser: https://localhost:8443
# Or via native DCV Viewer: localhost:8443
# Credentials: rockyuser / rocky

# Stop when done
docker stop rocky-dcv && docker rm rocky-dcv
```

#### DCV License (required for EC2)

DCV is free on EC2 but the instance must be able to reach the DCV license S3 bucket. The EC2 instance's IAM role needs this policy:

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

Replace `<region>` with your region (e.g. `us-west-2`). Without this, DCV will start but report "no license available" when clients connect.

#### DCV via SSM Port Forward

```bash
aws ssm start-session \
    --target <instance-id> \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["8443"],"localPortNumber":["8443"]}' \
    --region <region>
```

Then connect at `https://localhost:8443` (browser) or `localhost:8443` (native DCV Viewer).

Note: SSM tunneling is TCP-only, so DCV's QUIC/UDP transport won't be used. It falls back to WebSocket/TCP which still works well.

#### Host GPU Setup

The EC2 host running the container needs the NVIDIA driver, Docker, and NVIDIA Container Toolkit installed. See:
- [Install NVIDIA GPU driver, CUDA Toolkit, NVIDIA Container Toolkit on RHEL/Rocky Linux 8/9/10](https://repost.aws/articles/ARpmJcNiCtST2A3hrrM_4R4A/install-nvidia-gpu-driver-cuda-toolkit-nvidia-container-toolkit-on-amazon-ec2-instances-running-rhel-rocky-linux-8-9-10)
- `docker/README-nice-dcv.md` for a condensed host setup guide

## Quick Start

```bash
# 1. Generate the SSH tunnel key pair
bash generate_tunnel_key.sh

# 2. Provision EC2 proxy + VPC Lattice
python3 scripts/setup_infrastructure.py --create

# 3. Add the public key to the EC2 bastion
#    (via SSM — the ssm-user is created automatically on first session)
source creds.sh
aws ssm send-command --instance-ids i-0227d51eeadb27c64 --region us-west-2 \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"id ssm-user 2>/dev/null || useradd -m ssm-user\",\"mkdir -p /home/ssm-user/.ssh\",\"cat job/vnc_tunnel_key.pub >> /home/ssm-user/.ssh/authorized_keys\",\"chmod 700 /home/ssm-user/.ssh\",\"chmod 600 /home/ssm-user/.ssh/authorized_keys\",\"chown -R ssm-user:ssm-user /home/ssm-user/.ssh\"]"

# 4. Build and push Docker image
cd docker
docker build -t rocky-vnc:latest -f Dockerfile.rocky .
docker tag rocky-vnc:latest 257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo:rocky-vnc
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 257639634185.dkr.ecr.us-west-2.amazonaws.com
docker push 257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo:rocky-vnc

# 5. Attach VPC Lattice resource config to your Deadline fleet (console)
#    ARN: arn:aws:vpc-lattice:us-west-2:257639634185:resourceconfiguration/rcfg-0a8ab60ee0c8594b6

# 6. Submit the job
cd ../job
export EC2_PROXY_HOST=rcfg-0a8ab60ee0c8594b6.resource-endpoints.deadline.us-west-2.amazonaws.com
bash submit.sh

# 7. Connect from Mac
aws ssm start-session --target i-0227d51eeadb27c64 --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'

# 8. Open http://localhost:6080/vnc.html (password: password)
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
│   ├── Dockerfile.rocky               # GPU Rocky Linux + XFCE + noVNC (VNC)
│   ├── Dockerfile.rocky-nice-dcv      # GPU Rocky Linux + XFCE + Amazon DCV
│   ├── start.sh                       # VNC container entrypoint
│   ├── start-dcv.sh                   # DCV container entrypoint
│   ├── README.md                      # VNC container docs
│   └── README-nice-dcv.md             # DCV container docs (host setup, comparison)
├── job/
│   ├── template.yaml                  # Deadline job template
│   ├── submit.sh                      # Job submission script
│   └── README.md
├── scripts/
│   ├── setup_infrastructure.py        # One-shot infra provisioning
│   ├── host_config.sh                 # SMF worker host configuration
│   └── README.md
└── resources.json                     # Generated — resource IDs/ARNs
```

## See Also

- `ARCHITECTURE.md` — how the networking, tunnels, and VPC Lattice fit together
- `FARM_SETUP.md` — farm, fleet, queue, IAM roles, and VPC Lattice state
- `scripts/README.md` — infrastructure setup details
- `docker/README.md` — building and running the VNC container
- `docker/README-nice-dcv.md` — DCV container docs, host GPU setup, DCV vs VNC comparison
- `job/README.md` — job template and submission

## FAQ

**Job fails with `cp: cannot stat ... assetroot-...: No such file or directory`**

The SSH tunnel key (`vnc_tunnel_key`) is missing from the job bundle. The template expects it as a file attachment. Generate it:
```bash
bash generate_tunnel_key.sh
```
Then add the public key to the EC2 bastion (see step 3 in Quick Start).

**Job fails with `manifest for .../desktop-demo:rocky-vnc not found`**

The Docker image hasn't been pushed to ECR yet. Build, tag, and push:
```bash
source creds.sh
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 257639634185.dkr.ecr.us-west-2.amazonaws.com
cd docker
docker build -t rocky-vnc:latest -f Dockerfile.rocky .
docker tag rocky-vnc:latest 257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo:rocky-vnc
docker push 257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo:rocky-vnc
```

**SSM tunnel connects but browser shows nothing**

The Deadline job may still be starting, or the reverse SSH tunnel hasn't been established yet. Check the job logs in the Deadline console. The worker needs to pull the image, start the container, wait for noVNC, and then open the tunnel — this can take a few minutes on first run.

## Adding Your Workstation Key

Each user needs their own SSH key pair for the reverse tunnel. Generate one and register the public key on the EC2 bastion:

```bash
# 1. Generate your key (run from gui-demo/)
bash generate_tunnel_key.sh
# This creates job/vnc_tunnel_key and job/vnc_tunnel_key.pub

# 2. Register your public key on the bastion via SSM
source creds.sh
PUB_KEY=$(cat job/vnc_tunnel_key.pub)
aws ssm send-command --instance-ids i-0227d51eeadb27c64 --region us-west-2 \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"echo '$PUB_KEY' >> /home/ssm-user/.ssh/authorized_keys\"]"
```

Multiple users can each add their own key — the bastion's `authorized_keys` file accepts one key per line. No restart needed; sshd picks up new keys immediately.
