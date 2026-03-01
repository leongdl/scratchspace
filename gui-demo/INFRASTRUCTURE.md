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
│  │  │  │  EC2 Bastion     │    │  FSx for Lustre              │  │    │   │
│  │  │  │  t3.micro        │    │  PERSISTENT_2  1200 GB       │  │    │   │
│  │  │  │  10.0.0.57       │    │  125 MB/s/TiB                │  │    │   │
│  │  │  │  (reverse tunnel)│    │  /mnt/fsx                    │  │    │   │
│  │  │  └────────┬─────────┘    └──────────────────────────────┘  │    │   │
│  │  │           │                                                 │    │   │
│  │  │  ┌────────▼──────────────────────────────────────────────┐ │    │   │
│  │  │  │  Security Group  sg-0a0d2bdb7a935a990                 │ │    │   │
│  │  │  │  Inbound: 22, 988, 6080, 8188 from VPC CIDR           │ │    │   │
│  │  │  │           22, 6080, 8188 from VPC Lattice prefix list  │ │    │   │
│  │  │  └───────────────────────────────────────────────────────┘ │    │   │
│  │  │                                                             │    │   │
│  │  │  ┌──────────────────┐    ┌──────────────────────────────┐  │    │   │
│  │  │  │  VPCE — FSx      │    │  VPCE — SSM                  │  │    │   │
│  │  │  │  (Interface)     │    │  (Interface)                 │  │    │   │
│  │  │  │  Private DNS on  │    │  Private DNS on              │  │    │   │
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
│  │  ECR  257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo     │   │
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
              │  - Pulls container image from ECR               │
              │  - Mounts FSx at /mnt/fsx (shared assets)       │
              │  - Opens reverse SSH tunnel to bastion          │
              │  - VNC/noVNC served back through tunnel         │
              └─────────────────────────────────────────────────┘
```

---

## Components

### EC2 Bastion (`deadline-vnc-proxy`)
- `i-0227d51eeadb27c64` — t3.micro at `10.0.0.57`
- Lives in the private subnet with no public IP. Accessible only via SSM Session Manager or through the VPC Lattice endpoint.
- Configured on first boot (via user-data) with `GatewayPorts yes` in sshd, which allows Deadline workers to open a reverse SSH tunnel and bind it on `0.0.0.0` rather than loopback. This is what makes the VNC port reachable from outside the worker.
- Workers SSH in using a pre-shared key placed in `/home/ssm-user/.ssh/authorized_keys`.

### Security Group (`deadline-vnc-proxy-sg`)
- `sg-0a0d2bdb7a935a990`
- Shared by the EC2 bastion, FSx filesystem, and both VPC endpoints.
- Inbound rules are scoped to the VPC CIDR (`10.0.0.0/16`) and the VPC Lattice managed prefix list — no internet exposure.
- Ports: `22` (SSH tunnel), `988` (Lustre), `6080` (noVNC/HTTP), `8188` (ComfyUI).

### FSx for Lustre (`deadline-shared-fs`)
- `fs-0b20bb08cf7a694ed` — PERSISTENT_2, 1200 GB, 125 MB/s/TiB, no backups.
- Shared high-performance filesystem mounted by workers at `/mnt/fsx`. Used to distribute scene files, assets, and render outputs without copying data into each container.
- PERSISTENT_2 means data is replicated within the AZ and the file server is automatically replaced on failure — appropriate for production assets.
- Mount command: `mount -t lustre fs-0b20bb08cf7a694ed.fsx.us-west-2.amazonaws.com@tcp:/fdyl7b4v /mnt/fsx`
- Cost: ~$174/month (1200 GB × $0.145/GB-month, no backup charges).

### VPC Endpoint — FSx (`deadline-fsx-vpce`)
- `vpce-07af54c91a13de9da` — Interface endpoint for `com.amazonaws.us-west-2.fsx`
- Keeps FSx management traffic (mount, describe) inside the VPC. Private DNS enabled so the standard FSx DNS name resolves to a private IP automatically — no routing changes needed on workers.

### VPC Endpoint — SSM (`deadline-ssm-vpce`)
- `vpce-0982c820559b4b091` — Interface endpoint for `com.amazonaws.us-west-2.ssm`
- Allows SSM Session Manager to reach the bastion EC2 without an internet gateway or NAT. You can shell into the bastion with:
  ```
  aws ssm start-session --target i-0227d51eeadb27c64 --region us-west-2
  ```

### VPC Lattice Resource Gateway (`vnc-proxy-gateway`)
- `rgw-0e7bc6ca48da90534`
- The network bridge between Deadline's managed worker fleet (which runs in Deadline's own AWS account) and your private VPC. Workers reach the bastion's port 22 through this gateway without any VPC peering or public IPs.

### VPC Lattice Resource Configuration — Proxy (`vnc-proxy-config`)
- `rcfg-0a8ab60ee0c8594b6`
- Maps the Lattice endpoint to `10.0.0.57:22` (the bastion's private IP). Workers use this to open the reverse SSH tunnel:
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
4. The worker opens a reverse SSH tunnel to the bastion via the VPC Lattice endpoint (port 22), binding the VNC port (6080) on the bastion's `0.0.0.0`.
5. The operator connects to the bastion via SSM port forwarding and opens `http://localhost:6080/vnc.html` in a browser.

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
| Subnet | `subnet-044edd1290db6f355` | Private, us-west-2 |
| EC2 Bastion | `i-0227d51eeadb27c64` | `10.0.0.57`, t3.micro |
| Security Group | `sg-0a0d2bdb7a935a990` | Ports 22, 988, 6080, 8188 |
| FSx Filesystem | `fs-0b20bb08cf7a694ed` | 1200 GB PERSISTENT_2 |
| VPCE FSx | `vpce-07af54c91a13de9da` | Interface, private DNS |
| VPCE SSM | `vpce-0982c820559b4b091` | Interface, private DNS |
| Lattice Gateway | `rgw-0e7bc6ca48da90534` | ACTIVE |
| Lattice Config (proxy) | `rcfg-0a8ab60ee0c8594b6` | → 10.0.0.57:22 (SSH tunnel) |
| Lattice Config (FSx) | `rcfg-072853a357ca69135` | → FSx filesystem |
| RAM Share | `fbd340e3-5836-4aad-b9ec-c9b1e25efcb2` | Shared with Deadline fleet principal |
| ECR Repo | `desktop-demo` | `257639634185.dkr.ecr.us-west-2.amazonaws.com/desktop-demo` |
