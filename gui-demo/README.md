# gui-demo — Remote VNC Desktop on Deadline Cloud

Run a GPU-accelerated Rocky Linux desktop on Deadline Cloud Service-Managed Fleet workers and access it from your Mac's browser.

## Local Testing

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

## Quick Start

```bash
# 1. Generate the SSH tunnel key pair
bash generate_tunnel_key.sh

# 2. Provision EC2 proxy + VPC Lattice
python3 scripts/setup_infrastructure.py --create

# 3. Add the public key to the EC2 bastion
#    (via SSM or the EC2 serial console)
cat job/vnc_tunnel_key.pub >> /home/ssm-user/.ssh/authorized_keys

# 4. Build and push Docker image
cd docker
docker build -t rocky-vnc:latest -f Dockerfile.rocky .
docker tag rocky-vnc:latest 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:rocky-vnc
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:rocky-vnc

# 5. Attach VPC Lattice resource config to your Deadline fleet (console)

# 6. Submit the job
cd ../job
bash submit.sh

# 7. Connect from Mac
aws ssm start-session --target <instance-id> --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'

# 8. Open http://localhost:6080/vnc.html (password: password)
```

## Structure

```
gui-demo/
├── README.md                          # This file
├── ARCHITECTURE.md                    # End-to-end technical design
├── .gitignore                         # Excludes keys, pems, resources.json
├── generate_tunnel_key.sh             # Creates SSH key pair for the reverse tunnel
├── docker/
│   ├── Dockerfile.rocky               # GPU Rocky Linux + XFCE + noVNC
│   ├── start.sh                       # Container entrypoint
│   └── README.md
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
- `scripts/README.md` — infrastructure setup details
- `docker/README.md` — building and running the container
- `job/README.md` — job template and submission
