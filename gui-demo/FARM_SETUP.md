# Deadline Workstation Farm Setup

Current state of the Deadline Cloud farm, fleet, queue, and supporting infrastructure as provisioned by `scripts/setup_infrastructure.py`.

## Farm

| Field | Value |
|-------|-------|
| Farm ID | `farm-6c262cf737de4cb9b0c46f55f71cdaff` |
| Name | Dealine Workstation Farm |
| Region | us-west-2 |

## Queue

| Field | Value |
|-------|-------|
| Queue ID | `queue-6c7f40e315a44d0abb2cc169c0b85bb9` |
| Name | Workstation Queue |
| Status | SCHEDULING |
| Role | `AWSDeadlineCloudQueueRole-1872629856` |

## Fleet

| Field | Value |
|-------|-------|
| Fleet ID | `fleet-2c40b8e050c84233a834bb4d6dd8f08e` |
| Name | WorkstationFleet |
| Status | ACTIVE |
| Instance type | On-demand, 8-16 vCPU, 16-64 GB RAM |
| GPU | a10g, l4, or l40s (1 GPU) |
| OS | Linux x86_64 |
| Max workers | 1 |
| Role | `AWSDeadlineCloudFleetRole-467892534` |

## ECR Access

Both the fleet and queue roles have `AmazonEC2ContainerRegistryFullAccess` attached, so workers can authenticate to ECR and pull container images.

| Role | ECR Policy |
|------|------------|
| Fleet (`AWSDeadlineCloudFleetRole-467892534`) | `AmazonEC2ContainerRegistryFullAccess` |
| Queue (`AWSDeadlineCloudQueueRole-1872629856`) | `AmazonEC2ContainerRegistryFullAccess` |

ECR repository:
```
257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo
```

## VPC Lattice

The fleet has a VPC resource endpoint attached, allowing workers to initiate outbound connections to the EC2 bastion via a private DNS endpoint.

| Resource | ID / ARN |
|----------|----------|
| Resource Gateway | `rgw-0e7bc6ca48da90534` |
| Resource Configuration | `rcfg-0a8ab60ee0c8594b6` |
| Resource Config ARN | `arn:aws:vpc-lattice:us-west-2:257639634185:resourceconfiguration/rcfg-0a8ab60ee0c8594b6` |
| Worker Endpoint | `rcfg-0a8ab60ee0c8594b6.resource-endpoints.deadline.us-west-2.amazonaws.com` |
| Port | 22 (SSH) |
| RAM Share | `deadline-vnc-share` (ACTIVE) |
| RAM Share ARN | `arn:aws:ram:us-west-2:257639634185:resource-share/fbd340e3-5836-4aad-b9ec-c9b1e25efcb2` |
| Principal | `fleets.deadline.amazonaws.com` |

The resource configuration points to the EC2 bastion's private IP (`10.0.0.57`) on port 22. Workers SSH to the Lattice endpoint to establish reverse tunnels.

## EC2 Bastion

| Field | Value |
|-------|-------|
| Instance ID | `i-0227d51eeadb27c64` |
| Private IP | 10.0.0.57 |
| Type | t3.micro |
| Name | deadline-vnc-proxy |
| Key Pair | deadline-vnc-proxy-key |
| Security Group | `sg-0a0d2bdb7a935a990` (deadline-vnc-proxy-sg) |

### Security Group Rules (Inbound)

| Port | Source | Purpose |
|------|--------|---------|
| 22 | VPC CIDR (10.0.0.0/16) | SSH from VPC |
| 22 | VPC Lattice prefix list | SSH from SMF workers |
| 6080 | VPC CIDR | noVNC from VPC |
| 6080 | VPC Lattice prefix list | noVNC from SMF workers |
| 8188 | VPC CIDR | ComfyUI from VPC |
| 8188 | VPC Lattice prefix list | ComfyUI from SMF workers |

### sshd Configuration

User-data at launch configured:
- `GatewayPorts yes` — allows reverse tunnel `-R` to bind on `0.0.0.0`
- `/home/ssm-user/.ssh/authorized_keys` — prepared for worker tunnel keys

## Networking

```
VPC:    vpc-089c2522bf414cff2  (10.0.0.0/16)
Subnet: subnet-044edd1290db6f355  (10.0.0.0/24, us-west-2a)
```

All traffic between workers, VPC Lattice, and the EC2 bastion stays within AWS private networking. No public internet exposure.
