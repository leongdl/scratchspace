# Scripts

Infrastructure and host configuration scripts for the VNC proxy setup.

## Files

| File | Purpose |
|------|---------|
| `setup_infrastructure.py` | Creates EC2 proxy, security group, VPC Lattice, and RAM share. Outputs `resources.json`. |
| `host_config.sh` | Deadline SMF host configuration — installs Docker + NVIDIA container toolkit on workers. |

## Usage

### Provision infrastructure (one-time)

```bash
# Dry run — show current state
python3 setup_infrastructure.py

# Create everything
python3 setup_infrastructure.py --create
```

This creates the EC2 bastion, security group, VPC Lattice resource gateway/config, and RAM share. Outputs a `resources.json` with all IDs and ARNs.

### Host configuration

`host_config.sh` is used as the Deadline Cloud fleet host configuration script. It runs on each SMF worker at boot to install Docker and the NVIDIA runtime. Set it in the fleet's host configuration in the Deadline console.
