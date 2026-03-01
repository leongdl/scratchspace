# Infrastructure Design — Deadline Cloud VNC Demo

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AWS Account  (us-west-2)                                                   │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  VPC  vpc-089c2522bf414cff2  (10.0.0.0/16)                          │   │
│  │                                                                      │   │
│  │  ┌─────────────────────────────────────────────────────────────┐    │   │
│  │  │  Private Subnet  subnet-044edd1290db6f355                   │    │   │
│  │  │                                                             │    │   │
│  │  │  ┌──────────────────┐    ┌──────────────────────────────┐  │    │   │
│  │  │  │  EC2 Bastion     │    │  FSx for OpenZFS             │  │    │   │
│  │  │  │  t3.micro        │    │  SINGLE_AZ_1  64 GB          │  │    │   │
│  │  │  │  10.0.0.129      │    │  64 MB/s throughput          │  │    │   │
│  │  │  │  (reverse tunnel)│    │  /mnt/fsx  (NFS v4.1)        │  │    │   │
│  │  │  └────────┬─────────┘    └──────────────────────────────┘  │    │   │
│  │  │           │                                                 │    │   │
│  │  │  ┌────────▼──────────────────────────────────────────────┐ │    │   │
│  │  │  │  Security Group  sg-0a0d2bdb7a935a990                 │ │    │   │
│  │  │  │  Inbound: 22, 443, 2049, 6080, 8188 from VPC CIDR    │ │    │   │
│  │  │  │           22, 443, 2049, 6080, 8188 from Lattice      │ │    │   │
│  │  │  └───────────────────────────────────────────────────────┘ │    │   │
│  │  │                                                             │    │   │
│  │  │  ┌──────────────────┐    ┌──────────────────────────────┐  │    │   │
│  │  │  │  VPCE — FSx      │    │  VPCE — SSM (×3)             │  │    │   │
│  │  │  │  (Interface)     │    │  ssm, ssmmessages,           │  │    │   │
│  │  │  │  Private DNS on  │    │  ec2messages                 │  │    │   │
│  │  │  └──────────────────┘    └──────────────────────────────┘  │    │   │
│  │  └─────────────────────────────────────────────────────────────┘    │   │
│  │                                                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │  VPC Lattice                                                  │  │   │
│  │  │                                                               │  │   │
│  │  │  Resource Gateway  rgw-0e7bc6ca48da90534                      │  │   │
│  │  │       │                                                       │  │   │
│  │  │  Resource Config (proxy) rcfg-0a8ab60ee0c8594b6 → :22        │  │   │
│  │  │  Resource Config (fsx)   rcfg-072853a357ca69135 → FSx        │  │   │
│  │  │       │                                                       │  │   │
│  │  │  RAM Share ──────► fleets.deadline.amazonaws.com              │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                      │   │
│  │  ECR  257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo-dcv (active)  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘

                          ▲                        ▲
                          │  SSH reverse tunnel     │  SSM Session Manager
                          │  (port 22 via Lattice)  │  (no open ports needed)
                          │                         │
              ┌───────────┴─────────────────────────┴──────────┐
              │  Deadline Cloud Worker Fleet                    │
              │  (managed, runs in Deadline's account)          │
              │                                                 │
              │  - Pulls container image from ECR (desktop-demo-dcv:latest) │
              │  - Mounts FSx at /mnt/fsx via NFS (OpenZFS)             │
              │  - Opens reverse SSH tunnel to bastion (port 8443)      │
              │  - DCV desktop served back through tunnel                │
              └─────────────────────────────────────────────────┘
```

---

## Components

### EC2 Bastion (`deadline-vnc-proxy`)
- `i-06ff509b4812bc474` — t3.micro at `10.0.0.129`
- Lives in the private subnet with no public IP. Accessible only via SSM Session Manager or through the VPC Lattice endpoint.
- Configured on first boot (via user-data) with `GatewayPorts yes` in sshd, which allows Deadline workers to open a reverse SSH tunnel and bind it on `0.0.0.0` rather than loopback. This is what makes the VNC port reachable from outside the worker.
- Workers SSH in using a pre-shared key placed in `/home/ssm-user/.ssh/authorized_keys`.

### Security Group (`deadline-vnc-proxy-sg`)
- `sg-0a0d2bdb7a935a990`
- Shared by the EC2 bastion, FSx filesystem, and all VPC endpoints.
- Inbound rules are scoped to the VPC CIDR (`10.0.0.0/16`) and the VPC Lattice managed prefix list — no internet exposure.
- Ports: `22` (SSH tunnel), `443` (HTTPS for SSM VPC endpoints), `2049` (NFS for FSx OpenZFS), `6080` (noVNC/HTTP), `8188` (ComfyUI).

### FSx for OpenZFS (`deadline-shared-fs`)
- `fs-0fdcec1bc9f64d25d` — SINGLE_AZ_1, 64 GB SSD, 64 MB/s throughput, no backups.
- Shared filesystem mounted by workers at `/mnt/fsx` (bind-mounted from host `$HOME/fsx`). Used to distribute scene files, assets, and render outputs without copying data into each container.
- Mounted via NFS v4.1 through the VPC Lattice resource config endpoint.
- NFS export: `*` with `rw, crossmnt, no_root_squash, insecure` — `insecure` is required because the NFS client port comes through the Lattice proxy and may be unprivileged.
- Cost: ~$6/month (64 GB × $0.09/GB-month).

### VPC Endpoint — FSx (`deadline-fsx-vpce`)
- `vpce-07af54c91a13de9da` — Interface endpoint for `com.amazonaws.us-west-2.fsx`
- Keeps FSx management traffic (mount, describe) inside the VPC. Private DNS enabled so the standard FSx DNS name resolves to a private IP automatically — no routing changes needed on workers.

### VPC Endpoint — SSM (`deadline-ssm-vpce`)
- `vpce-0982c820559b4b091` — Interface endpoint for `com.amazonaws.us-west-2.ssm`
- `vpce-09c601780831989c7` — Interface endpoint for `com.amazonaws.us-west-2.ssmmessages`
- `vpce-079b7bffde14368e8` — Interface endpoint for `com.amazonaws.us-west-2.ec2messages`
- All three are required for SSM Session Manager to work in a private subnet. Private DNS enabled on all. You can shell into the bastion with:
  ```
  aws ssm start-session --target i-06ff509b4812bc474 --region us-west-2
  ```

### VPC Lattice Resource Gateway (`vnc-proxy-gateway`)
- `rgw-0e7bc6ca48da90534`
- The network bridge between Deadline's managed worker fleet (which runs in Deadline's own AWS account) and your private VPC. Workers reach the bastion's port 22 through this gateway without any VPC peering or public IPs.

### VPC Lattice Resource Configuration — Proxy (`vnc-proxy-config`)
- `rcfg-0a8ab60ee0c8594b6`
- Maps the Lattice endpoint to `10.0.0.129:22` (the bastion's private IP). Workers use this to open the reverse SSH tunnel:
  ```
  rcfg-0a8ab60ee0c8594b6.resource-endpoints.deadline.us-west-2.amazonaws.com:22
  ```

### VPC Lattice Resource Configuration — FSx (`vnc-proxy-config`)
- `rcfg-072853a357ca69135`
- Maps the Lattice endpoint to the FSx filesystem. Workers use this to mount the shared filesystem:
  ```
  rcfg-072853a357ca69135.resource-endpoints.deadline.us-west-2.amazonaws.com
  ```

### RAM Share (`deadline-vnc-share`)
- `arn:aws:ram:us-west-2:257639634185:resource-share/fbd340e3-5836-4aad-b9ec-c9b1e25efcb2`
- Shares the VPC Lattice resource configuration with the `fleets.deadline.amazonaws.com` service principal, which is what allows Deadline workers in a separate account to resolve and connect to the Lattice endpoint.

### ECR Repository (`desktop-demo`)
- `257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo`
- Stores the container image that workers pull and run. The image contains the desktop environment (Rocky Linux + VNC/noVNC or NICE DCV) and any pre-installed software.

---

## Data Flow

1. Deadline submits a job and spins up a worker in its managed fleet.
2. The worker pulls the container image from ECR.
3. The worker mounts the FSx filesystem at `/mnt/fsx` for shared assets.
4. The worker opens a reverse SSH tunnel to the bastion via the VPC Lattice endpoint (port 22), binding the DCV port (8443) on the bastion's `0.0.0.0`.
5. The operator connects to the bastion via SSM port forwarding and opens `https://localhost:8443` in a browser — credentials `rockyuser / rocky`.

---

## Setup Script

All resources are provisioned by `gui-demo/scripts/setup_infrastructure.py`.

The script is fully **idempotent** — every create function checks for an existing resource by name/tag before attempting to create it. Running it multiple times is safe and will simply report existing resources as `○ already exists`. This makes it suitable for CI, re-runs after partial failures, or onboarding new team members without risk of duplicate resources.

```bash
# Dry run — check current state, write resources.json with nulls for missing resources
source creds.sh && python3 gui-demo/scripts/setup_infrastructure.py

# Create all missing resources
source creds.sh && python3 gui-demo/scripts/setup_infrastructure.py --create

# Custom output path
source creds.sh && python3 gui-demo/scripts/setup_infrastructure.py --create --output my-resources.json
```

The output manifest (`gui-demo/resources.json`) is written on every run — including dry runs — with `null` for any resource not yet created. Job templates and scripts can source this file for all IDs and endpoints.

---

## Resource Summary

| Resource | ID | Notes |
|---|---|---|
| VPC | `vpc-089c2522bf414cff2` | `10.0.0.0/16` |
| Subnet | `subnet-044edd1290db6f355` | us-west-2a |
| EC2 Bastion | `i-06ff509b4812bc474` | `10.0.0.129`, t3.micro, SSMManagedEC2Role |
| Security Group | `sg-0a0d2bdb7a935a990` | Ports 22, 443, 2049, 6080, 8188 |
| FSx OpenZFS | `fs-0fdcec1bc9f64d25d` | 64 GB SINGLE_AZ_1, NFS v4.1 |
| VPCE FSx | `vpce-07af54c91a13de9da` | Interface, private DNS |
| VPCE SSM | `vpce-0982c820559b4b091` | Interface, private DNS |
| VPCE SSM Messages | `vpce-09c601780831989c7` | Interface, private DNS |
| VPCE EC2 Messages | `vpce-079b7bffde14368e8` | Interface, private DNS |
| Lattice Gateway | `rgw-0e7bc6ca48da90534` | ACTIVE |
| Lattice Config (proxy) | `rcfg-0a8ab60ee0c8594b6` | → 10.0.0.129:22 (SSH tunnel) |
| Lattice Config (FSx) | `rcfg-072853a357ca69135` | → 10.0.0.148:2049 (NFS) |
| RAM Share | `fbd340e3-5836-4aad-b9ec-c9b1e25efcb2` | Shared with Deadline fleet principal |
| ECR Repo (active) | `desktop-demo-dcv` | `257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo-dcv:latest` |
| ECR Repo (fallback) | `desktop-demo` | `257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo:rocky-vnc` |
