# VNC Remote Desktop via Deadline Cloud SMF - User Guide

Access a Rocky Linux VNC desktop running on Deadline Cloud Service-Managed Fleet workers from your Mac.

## 1. Build and Upload Docker Image

```bash
# Login to ECR and build/push the image
source scripts/creds.sh
bash scripts/build_and_push.sh
```

This builds `Dockerfile.rocky` (Rocky Linux 9 + XFCE + noVNC) and pushes to:
`224071664257.dkr.ecr.us-west-2.amazonaws.com/sqex2:rocky-vnc`

## 2. EC2 Bastion Host Setup

On the EC2 bastion (i-0dafdfc660885e366):

1. **Enable SSH remote port forwarding** in `/etc/ssh/sshd_config`:
   ```
   GatewayPorts yes
   ```
   Then restart: `sudo systemctl restart sshd`

2. **Add the worker's SSH public key** to `~/.ssh/authorized_keys`:
   ```bash
   cat job/vnc_tunnel_key.pub >> ~/.ssh/authorized_keys
   ```

3. **VPC Lattice** must be configured to expose port 22 (SSH) to the EC2's private IP. The resource configuration endpoint is:
   ```
   rcfg-011bc61e9efbfbd1e.resource-endpoints.deadline.us-west-2.amazonaws.com
   ```

## 3. Connect from Mac

Start an SSM port forwarding session to the EC2 bastion:

```bash
aws ssm start-session --target i-0dafdfc660885e366 --region us-west-2 \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'
```

Once the job is running and the reverse tunnel is established, open:
- **URL**: http://localhost:6080/vnc.html
- **Password**: `password`

## 4. Submit Job

```bash
source scripts/creds.sh
bash scripts/submit_job.sh
```

### How the Job Works

1. **Pulls Docker image** from ECR
2. **Starts VNC container** with `--network host` so noVNC listens on port 6080
3. **Establishes reverse SSH tunnel** to EC2 bastion via VPC Lattice endpoint
   - Worker connects to `rcfg-...resource-endpoints.deadline.us-west-2.amazonaws.com:22`
   - Creates tunnel: EC2:6080 → Worker:6080
4. **Keeps session alive** for the configured duration (default 1 hour)
5. **Cleans up** container and tunnel when session ends

### Traffic Flow

```
Mac:6080 → SSM Tunnel → EC2:6080 → Reverse SSH Tunnel → Worker:6080 (noVNC)
```

The worker initiates the connection outbound via VPC Lattice, so no inbound access to the worker is needed.

## 5. VPC Lattice, RAM, and Fleet Configuration

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Your AWS Account                                │
│                                                                              │
│  ┌──────────────┐     ┌─────────────────────┐     ┌────────────────────┐   │
│  │     Mac      │     │    Your VPC         │     │  Deadline Cloud    │   │
│  │              │     │                     │     │  (AWS Managed)     │   │
│  │  localhost   │     │  ┌───────────────┐  │     │                    │   │
│  │    :6080     │────▶│  │ EC2 Bastion   │  │     │  ┌──────────────┐  │   │
│  │              │ SSM │  │ 10.0.0.65:22  │◀─┼─────┼──│ SMF Worker   │  │   │
│  └──────────────┘     │  │        :6080  │  │ VPC │  │              │  │   │
│                       │  └───────────────┘  │Lattice│ │ Docker:6080 │  │   │
│                       │         ▲           │     │  └──────────────┘  │   │
│                       │         │           │     │                    │   │
│                       │  ┌──────┴────────┐  │     └────────────────────┘   │
│                       │  │Resource Gateway│  │                              │
│                       │  │ (VPC Lattice) │  │                              │
│                       │  └───────────────┘  │                              │
│                       └─────────────────────┘                              │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         VPC Lattice                                  │   │
│  │  Resource Config ──▶ Resource Gateway ──▶ EC2 Private IP:22         │   │
│  │  (rcfg-xxx)          (rgw-xxx)            (10.0.0.65)               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         AWS RAM                                      │   │
│  │  Resource Share ──▶ Principal: fleets.deadline.amazonaws.com        │   │
│  │  (deadline-vnc-share)                                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Setup Steps

#### 1. Create Resource Gateway

```bash
aws vpc-lattice create-resource-gateway \
  --name vnc-proxy-gateway \
  --vpc-identifier vpc-0e8e227f1094b2f9a \
  --subnet-ids subnet-0f145f86a08d5f76e \
  --security-group-ids sg-09d332611399f751a
```

#### 2. Create Resource Configuration

Point to your EC2 bastion's private IP and SSH port:

```bash
aws vpc-lattice create-resource-configuration \
  --name vnc-proxy-config \
  --type SINGLE \
  --port-ranges "22" \
  --protocol TCP \
  --resource-gateway-identifier rgw-xxx \
  --resource-configuration-definition "ipResource={ipAddress=10.0.0.65}"
```

#### 3. Create RAM Share

Share the resource configuration with Deadline Cloud:

```bash
aws ram create-resource-share \
  --name deadline-vnc-share \
  --resource-arns arn:aws:vpc-lattice:us-west-2:ACCOUNT:resourceconfiguration/rcfg-xxx \
  --principals fleets.deadline.amazonaws.com
```

#### 4. Attach to Deadline Fleet

In the Deadline Cloud console:
1. Go to Farms → Your Farm → Fleets → Your Fleet
2. Click Configurations tab
3. Under VPC resource endpoints, click Edit
4. Select your resource configuration and Save

Or via CLI:

```bash
aws deadline update-fleet \
  --farm-id farm-xxx \
  --fleet-id fleet-xxx \
  --configuration '{
    "serviceManagedEc2": {
      "vpcConfiguration": {
        "resourceConfigurationArns": ["arn:aws:vpc-lattice:us-west-2:ACCOUNT:resourceconfiguration/rcfg-xxx"]
      }
    }
  }'
```

### Verify Setup

```bash
# Check resource configuration
aws vpc-lattice get-resource-configuration --resource-configuration-identifier rcfg-xxx

# Check RAM share status
aws ram get-resource-shares --resource-owner SELF

# Check fleet has the resource config attached
aws deadline get-fleet --farm-id farm-xxx --fleet-id fleet-xxx \
  --query 'configuration.serviceManagedEc2.vpcConfiguration'
```

The endpoint for workers is: `rcfg-xxx.resource-endpoints.deadline.REGION.amazonaws.com`
