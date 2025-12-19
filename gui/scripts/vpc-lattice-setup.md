# VPC Lattice Setup for Deadline Cloud SMF

This guide documents how to connect Deadline Cloud Service-Managed Fleet (SMF) workers to an EC2 proxy instance using VPC Lattice resource endpoints.

## Architecture

```
SMF Worker (noVNC on port 6080)
    |
    | Reverse SSH tunnel (worker initiates)
    v
VPC Lattice Resource Endpoint
    |
    | <resource-config-id>.resource-endpoints.deadline.<region>.amazonaws.com:6688
    |
    v
Resource Gateway (ENIs in your VPC)
    |
    v
EC2 Proxy Instance (10.0.0.65)
    |
    | socat: 6688 -> 6080
    |
    | SSM Port Forward
    v
Mac (localhost:6080 -> noVNC web UI)
```

## Key Concepts

### Unidirectional Traffic
VPC Lattice resource endpoints are **unidirectional**: SMF workers can initiate connections TO your VPC resources, but your VPC resources cannot initiate connections TO workers.

For VNC access, this means:
1. Worker runs noVNC server on port 6080
2. Worker initiates reverse SSH tunnel to EC2 proxy via VPC Lattice
3. EC2 proxy can then reach worker's noVNC through the established tunnel

### Resource Components
1. **Resource Gateway** - Creates ENIs in your VPC subnet to route VPC Lattice traffic
2. **Resource Configuration** - Defines the target (EC2 IP + port) that workers connect to
3. **RAM Share** - Shares the resource config with Deadline Cloud service principal
4. **Fleet VPC Configuration** - Attaches the resource config to your SMF fleet

## Security Analysis

### Why This Setup is Safe (No Public Internet Exposure)

The script adds two types of security group rules:

#### 1. VPC CIDR Rule (`10.0.0.0/16`)
- **Source**: Your VPC's private CIDR block only
- **Purpose**: Allows direct access from other resources in your VPC (useful for testing)
- **Safety**: RFC 1918 private addresses cannot originate from the public internet

#### 2. VPC Lattice Prefix List Rule
- **Source**: AWS-managed prefix list `com.amazonaws.<region>.vpc-lattice`
- **Purpose**: Allows traffic from VPC Lattice resource gateways
- **Safety**: VPC Lattice is a private AWS service - traffic flows over AWS backbone, never the internet

### What Would Expose to Internet (NOT done by this script)
- Adding `0.0.0.0/0` inbound rules
- Attaching an Elastic IP to the EC2
- Placing behind a public load balancer
- Adding routes to an Internet Gateway

### Traffic Flow Security
```
SMF Worker (AWS-managed, no direct access)
    ↓ (AWS internal backbone)
VPC Lattice Service
    ↓ (AWS internal backbone)
Resource Gateway ENI (private IP in your subnet)
    ↓ (VPC internal)
EC2 Instance (private IP only)
```

All traffic stays within AWS private networking. No internet path exists.

## Current Environment

From `configure_smf_vpc.md`:
```
EC2 Instance: i-0dafdfc660885e366
VPC: vpc-0e8e227f1094b2f9a (CIDR: 10.0.0.0/16)
Subnet: subnet-0f145f86a08d5f76e (CIDR: 10.0.0.0/24, AZ: us-west-2a)
Security Group: sg-09d332611399f751a
EC2 Private IP: 10.0.0.65

Farm: farm-fd8e9a84d9c04142848c6ea56c9d7568
Fleet: fleet-8eebe8e8dc07489d97e6641aab3ad6fa
Queue: queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38
```

## Setup Script

Use `setup_vpc_lattice.py` for idempotent setup:

```bash
# Check current state (no changes)
python3 setup_vpc_lattice.py

# Add security group rules only
python3 setup_vpc_lattice.py --add-rules

# Create VPC Lattice resources only
python3 setup_vpc_lattice.py --create

# Full setup: rules + resources + fleet update
python3 setup_vpc_lattice.py --full
```

### Idempotency
The script is safe to run multiple times:
- Checks for existing resources by name before creating
- Security group duplicate rules are caught and skipped
- Fleet update checks if ARN already attached

### Resources Created
| Resource | Name | Purpose |
|----------|------|---------|
| Resource Gateway | `vnc-proxy-gateway` | Routes VPC Lattice traffic to your VPC |
| Resource Configuration | `vnc-proxy-config` | Points to EC2 at 10.0.0.65:6688 |
| RAM Share | `deadline-vnc-share` | Shares with `fleets.deadline.amazonaws.com` |

## Security Group Rules Added

| Port | Source | Description |
|------|--------|-------------|
| 22 | 10.0.0.0/16 | SSH from VPC |
| 22 | VPC Lattice prefix | SSH from SMF via Lattice |
| 6080 | 10.0.0.0/16 | noVNC from VPC |
| 6080 | VPC Lattice prefix | noVNC from SMF via Lattice |
| 6688 | 10.0.0.0/16 | Proxy port from VPC |
| 6688 | VPC Lattice prefix | Proxy port from SMF via Lattice |

## After Setup

Workers access the EC2 proxy at:
```
<resource-config-id>.resource-endpoints.deadline.us-west-2.amazonaws.com:6688
```

This endpoint is:
- Private (not resolvable from internet or your workstation)
- Only accessible from SMF workers with the resource config attached
- Routed through VPC Lattice to your EC2's private IP

## Troubleshooting

### Resource Gateway not ACTIVE
- Check subnet has available IPs
- Verify security group allows outbound traffic
- Wait a few minutes for ENI provisioning

### Workers can't connect
- Verify RAM share status is ACTIVE
- Check fleet has resource config attached
- Ensure resource config status is ACTIVE
- Verify security group has VPC Lattice prefix list rules

### Connection works but VNC doesn't display
- Verify socat is running on EC2 (`socat TCP-LISTEN:6688,fork TCP:localhost:6080`)
- Check reverse SSH tunnel from worker is established
- Verify noVNC is running in worker container on port 6080
