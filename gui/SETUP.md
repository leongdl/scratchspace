# Clean Setup Guide: Remote Desktop & ComfyUI on Deadline Cloud SMF

This guide walks through setting up remote GUI access (VNC or ComfyUI) to Deadline Cloud Service-Managed Fleet workers via an EC2 bastion and VPC Lattice.

## Architecture

```
Mac (browser)                EC2 Bastion              VPC Lattice              Deadline SMF Worker
localhost:PORT  ──SSM──▶  10.0.0.65:PORT  ◀──reverse SSH──  Worker:PORT (Docker --network host)
```

The worker initiates all connections outbound. No inbound access to the worker is needed.

| Application | Port |
|-------------|------|
| noVNC (VNC) | 6080 |
| ComfyUI     | 8188 |

## Prerequisites

- AWS CLI v2 with SSM plugin installed on your Mac
- An AWS account with Deadline Cloud farm, fleet, and queue already created
- An EC2 instance in the same VPC (acts as bastion/proxy)
- Docker installed locally (for building images)

## Environment Reference

```
EC2 Instance:   i-0dafdfc660885e366  (Private IP: 10.0.0.65)
VPC:            vpc-0e8e227f1094b2f9a
Subnet:         subnet-0f145f86a08d5f76e
Security Group: sg-09d332611399f751a
Farm:           farm-fd8e9a84d9c04142848c6ea56c9d7568
Fleet:          fleet-8eebe8e8dc07489d97e6641aab3ad6fa
Queue:          queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38
ECR Registry:   224071664257.dkr.ecr.us-west-2.amazonaws.com
VPC Lattice:    rcfg-011bc61e9efbfbd1e.resource-endpoints.deadline.us-west-2.amazonaws.com
```

---

## Step 1: Build and Push Docker Image

### VNC Desktop (Rocky Linux + XFCE)

```bash
# Login to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin 224071664257.dkr.ecr.us-west-2.amazonaws.com

# Build
docker build -t sqex2:rocky-vnc -f gui/Dockerfile.rocky gui/

# Tag and push
docker tag sqex2:rocky-vnc 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:rocky-vnc
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:rocky-vnc
```

### ComfyUI (with GPU support)

```bash
# Build base
docker build -t comfyui-rocky:latest gui/comfyui/

# Build with pre-baked models (e.g. SDXL, Hunyuan3D)
docker build -f gui/comfyui/Dockerfile.sdxl -t comfyui-sdxl:latest gui/comfyui/
docker build -f gui/comfyui/Dockerfile.hunyuan3d -t comfyui-hunyuan3d:latest gui/comfyui/

# Tag and push
docker tag comfyui-hunyuan3d:latest 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-hunyuan3d:latest
docker push 224071664257.dkr.ecr.us-west-2.amazonaws.com/comfyui-hunyuan3d:latest
```

Create ECR repos if needed:
```bash
aws ecr create-repository --repository-name sqex2 --region us-west-2
aws ecr create-repository --repository-name comfyui-hunyuan3d --region us-west-2
```

---

## Step 2: Configure the EC2 Bastion

SSH into the EC2 instance (or use SSM) and run:

```bash
# Install socat and configure SSH
sudo yum install -y socat openssh-server
sudo systemctl enable sshd && sudo systemctl start sshd

# Enable reverse tunnel binding on all interfaces
sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
sudo sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
grep -q "^GatewayPorts yes" /etc/ssh/sshd_config || echo "GatewayPorts yes" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd

# Open firewall if firewalld is active
if systemctl is-active --quiet firewalld; then
  sudo firewall-cmd --permanent --add-port=6080/tcp
  sudo firewall-cmd --permanent --add-port=8188/tcp
  sudo firewall-cmd --reload
fi
```

Or just run the provided script:
```bash
bash gui/scripts/ec2-setup.sh
```

### SSH Key Setup

Generate a key pair for the reverse tunnel. The private key goes with the Deadline job, the public key goes on the EC2:

```bash
ssh-keygen -t rsa -b 4096 -f vnc_tunnel_key -N "" -C "deadline-worker-tunnel"

# Add public key to EC2 bastion
cat vnc_tunnel_key.pub >> /home/ssm-user/.ssh/authorized_keys
```

Place `vnc_tunnel_key` in the job bundle directory (e.g. `gui/job/vnc_tunnel_key`).

---

## Step 3: Set Up VPC Lattice

VPC Lattice creates a private path from SMF workers to your EC2 bastion. Workers connect to a private DNS endpoint that routes through VPC Lattice to the EC2's private IP.

### Option A: Automated (Python script)

```bash
# Dry run — check current state
python3 gui/scripts/setup_vpc_lattice.py

# Add security group rules only
python3 gui/scripts/setup_vpc_lattice.py --add-rules

# Full setup: SG rules + Resource Gateway + Resource Config + RAM Share + Fleet update
python3 gui/scripts/setup_vpc_lattice.py --full
```

The script is idempotent — safe to run multiple times.

### Option B: Manual (AWS CLI)

#### 3a. Security Group Rules

Allow traffic from VPC CIDR and VPC Lattice prefix list on ports 22, 6080, 6688:

```bash
# Get VPC Lattice prefix list
PL_ID=$(aws ec2 describe-managed-prefix-lists \
  --filters "Name=prefix-list-name,Values=com.amazonaws.us-west-2.vpc-lattice" \
  --query 'PrefixLists[0].PrefixListId' --output text)

# Add rules for each port
for PORT in 22 6080 6688; do
  aws ec2 authorize-security-group-ingress --group-id sg-09d332611399f751a \
    --protocol tcp --port $PORT --cidr 10.0.0.0/16
  aws ec2 authorize-security-group-ingress --group-id sg-09d332611399f751a \
    --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,PrefixListIds=[{PrefixListId=$PL_ID}]"
done
```

#### 3b. Create Resource Gateway

```bash
aws vpc-lattice create-resource-gateway \
  --name vnc-proxy-gateway \
  --vpc-identifier vpc-0e8e227f1094b2f9a \
  --subnet-ids subnet-0f145f86a08d5f76e \
  --security-group-ids sg-09d332611399f751a
```

#### 3c. Create Resource Configuration

Point to EC2 bastion's SSH port:

```bash
aws vpc-lattice create-resource-configuration \
  --name vnc-proxy-config \
  --type SINGLE \
  --port-ranges "22" \
  --protocol TCP \
  --resource-gateway-identifier <rgw-id-from-above> \
  --resource-configuration-definition "ipResource={ipAddress=10.0.0.65}"
```

#### 3d. Share via RAM

```bash
aws ram create-resource-share \
  --name deadline-vnc-share \
  --resource-arns arn:aws:vpc-lattice:us-west-2:224071664257:resourceconfiguration/<rcfg-id> \
  --principals fleets.deadline.amazonaws.com
```

#### 3e. Attach to Fleet

In Deadline Cloud console: Farms → Fleet → Configurations → VPC resource endpoints → Edit → Select your resource config → Save.

Or via CLI:
```bash
aws deadline update-fleet \
  --farm-id farm-fd8e9a84d9c04142848c6ea56c9d7568 \
  --fleet-id fleet-8eebe8e8dc07489d97e6641aab3ad6fa \
  --configuration '{"serviceManagedEc2":{"vpcConfiguration":{"resourceConfigurationArns":["arn:aws:vpc-lattice:us-west-2:224071664257:resourceconfiguration/<rcfg-id>"]}}}'
```

### Verify

```bash
bash gui/scripts/check_lattice.sh   # Resource config status
bash gui/scripts/check_ram.sh       # RAM share status
bash gui/scripts/check_fleet.sh     # Fleet VPC config
```

---

## Step 4: GPU Host Setup (for ComfyUI workers)

If your SMF fleet uses GPU instances, the host needs NVIDIA container toolkit configured. Use the provided script in the fleet's host configuration:

```bash
bash gui/design/setup_gpu_docker.sh
```

This installs Docker, NVIDIA container toolkit 1.18.2, configures the `--runtime=nvidia` workaround (needed for driver 580.x BPF bug), generates CDI spec, and creates swap for large model loading.

Key point: use `--runtime=nvidia` with env vars instead of `--gpus all`:
```bash
docker run --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --network host \
  ...
```

---

## Step 5: Submit a Job

### VNC Desktop

```bash
cd gui/job
deadline bundle submit . \
  --farm-id farm-fd8e9a84d9c04142848c6ea56c9d7568 \
  --queue-id queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38 \
  --name "VNC-Desktop-$(date +%Y%m%d-%H%M%S)" \
  --max-retries-per-task 1
```

### ComfyUI

```bash
cd gui/comfyui/job
deadline bundle submit . \
  --farm-id farm-fd8e9a84d9c04142848c6ea56c9d7568 \
  --queue-id queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38 \
  --name "ComfyUI-$(date +%Y%m%d-%H%M%S)" \
  --max-retries-per-task 1
```

The job template will:
1. Pull the Docker image from ECR
2. Start the container with `--network host`
3. Wait for the app to be ready (port check)
4. Establish a reverse SSH tunnel to the EC2 bastion via VPC Lattice
5. Keep the session alive for the configured duration (default 1h for VNC, 3h for ComfyUI)
6. Clean up on exit

---

## Step 6: Connect from Your Mac

### Start SSM Tunnel

For VNC:
```bash
aws ssm start-session --target i-0dafdfc660885e366 --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'
```

For ComfyUI:
```bash
aws ssm start-session --target i-0dafdfc660885e366 --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8188"],"localPortNumber":["8188"]}'
```

Or use the provided scripts:
```bash
bash gui/scripts/mac-tunnel.sh          # VNC (port 6080)
bash gui/comfyui/scripts/mac-tunnel.sh  # ComfyUI (port 8188)
```

### Open in Browser

- VNC: http://localhost:6080/vnc.html (password: `password`)
- ComfyUI: http://localhost:8188

---

## Traffic Flow Summary

```
Mac:PORT ──SSM tunnel──▶ EC2:PORT ◀──reverse SSH tunnel── Worker:PORT (Docker)
                                    via VPC Lattice endpoint
```

All traffic stays within AWS private networking. No internet exposure.

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Can't connect from Mac | Is SSM session active? `aws ssm start-session ...` |
| SSM connects but page doesn't load | Is the Deadline job running? Check Deadline console |
| Job running but no tunnel | Check job logs for SSH errors. Verify SSH key is in EC2 authorized_keys |
| SSH tunnel fails | Verify `GatewayPorts yes` in EC2 sshd_config. Check SG allows port 22 from VPC Lattice |
| Container won't start | Check ECR login succeeded. Check `docker pull` in job logs |
| GPU not detected (ComfyUI) | Use `--runtime=nvidia` not `--gpus all`. Run `setup_gpu_docker.sh` on host |
| Docker run hangs on large images | Normal for >50GB images. EBS throughput bottleneck. Wait 10-20 min or increase gp3 throughput |
| Port already in use | Previous job didn't clean up. Job template handles this with cleanup at start |
| VPC Lattice endpoint unreachable | Check RAM share is ACTIVE. Check fleet has resource config attached |
