#!/usr/bin/env python3
"""
Infrastructure Setup for Deadline Cloud SMF VNC Access

Creates:
  1. Security group for the EC2 proxy bastion
  2. SSH key pair for the reverse tunnel
  3. EC2 T3 instance with user-data that configures GatewayPorts + sshd
  4. VPC Lattice resource gateway + resource configuration (port 22)
  5. RAM share with fleets.deadline.amazonaws.com

Outputs a JSON file with all resource IDs/ARNs so the job template can reference them.

Idempotent — safe to run multiple times. Finds existing resources by Name tag / name field.

Usage:
  python3 setup_infrastructure.py                # Dry run — show what exists
  python3 setup_infrastructure.py --create       # Create everything
  python3 setup_infrastructure.py --create --output resources.json
"""

import argparse
import json
import sys
import time
import textwrap
from typing import Optional

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Configuration — edit these to match your environment
# ---------------------------------------------------------------------------
CONFIG = {
    "region": "us-west-2",
    "vpc_id": "vpc-089c2522bf414cff2",
    "subnet_id": "subnet-044edd1290db6f355",
    # EC2 proxy
    "instance_type": "t3.micro",
    "instance_name": "deadline-vnc-proxy",
    "key_pair_name": "deadline-vnc-proxy-key",
    "sg_name": "deadline-vnc-proxy-sg",
    "ami_ssm_param": "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64",
    # VPC Lattice
    "resource_gateway_name": "vnc-proxy-gateway",
    "resource_config_name": "vnc-proxy-config",
    "ram_share_name": "deadline-vnc-share",
    # Ports exposed through the security group
    "ports": [22, 6080, 8188],
    # ECR
    "ecr_repo_name": "desktop-demo",
}

# ---------------------------------------------------------------------------
# User-data script — runs once on first boot
# Configures sshd for reverse tunnels. No socat needed; workers SSH directly.
# ---------------------------------------------------------------------------
USER_DATA = textwrap.dedent("""\
    #!/bin/bash
    set -e

    # --- SSH reverse-tunnel support ---
    # Enable GatewayPorts so -R binds on 0.0.0.0 instead of 127.0.0.1
    sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
    sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
    grep -q "^GatewayPorts yes" /etc/ssh/sshd_config || echo "GatewayPorts yes" >> /etc/ssh/sshd_config
    systemctl restart sshd

    # --- Prepare the ssm-user account for tunnel keys ---
    mkdir -p /home/ssm-user/.ssh
    chmod 700 /home/ssm-user/.ssh
    touch /home/ssm-user/.ssh/authorized_keys
    chmod 600 /home/ssm-user/.ssh/authorized_keys
    chown -R ssm-user:ssm-user /home/ssm-user/.ssh

    echo "EC2 proxy setup complete — ready for reverse SSH tunnels"
""")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def get_clients():
    region = CONFIG["region"]
    return (
        boto3.client("ec2", region_name=region),
        boto3.client("vpc-lattice", region_name=region),
        boto3.client("ram", region_name=region),
        boto3.client("ssm", region_name=region),
        boto3.client("sts", region_name=region),
        boto3.client("ecr", region_name=region),
    )


def find_instance_by_name(ec2, name: str) -> Optional[dict]:
    """Find a running/pending/stopped instance by its Name tag."""
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Name", "Values": [name]},
            {"Name": "instance-state-name", "Values": ["running", "pending", "stopped"]},
        ]
    )
    for res in resp.get("Reservations", []):
        for inst in res.get("Instances", []):
            return inst
    return None


def find_sg_by_name(ec2, name: str, vpc_id: str) -> Optional[dict]:
    resp = ec2.describe_security_groups(
        Filters=[
            {"Name": "group-name", "Values": [name]},
            {"Name": "vpc-id", "Values": [vpc_id]},
        ]
    )
    sgs = resp.get("SecurityGroups", [])
    return sgs[0] if sgs else None


def find_key_pair(ec2, name: str) -> Optional[dict]:
    try:
        resp = ec2.describe_key_pairs(KeyNames=[name])
        return resp["KeyPairs"][0] if resp.get("KeyPairs") else None
    except ClientError as e:
        if "InvalidKeyPair.NotFound" in str(e):
            return None
        raise


def find_resource_gateway(vpc_lattice, name: str) -> Optional[dict]:
    try:
        for page in vpc_lattice.get_paginator("list_resource_gateways").paginate():
            for gw in page.get("items", []):
                if gw.get("name") == name:
                    return gw
    except ClientError:
        pass
    return None


def find_resource_config(vpc_lattice, name: str) -> Optional[dict]:
    try:
        for page in vpc_lattice.get_paginator("list_resource_configurations").paginate():
            for cfg in page.get("items", []):
                if cfg.get("name") == name:
                    return cfg
    except ClientError:
        pass
    return None


def find_ram_share(ram, name: str) -> Optional[dict]:
    try:
        for page in ram.get_paginator("get_resource_shares").paginate(resourceOwner="SELF"):
            for share in page.get("resourceShares", []):
                if share.get("name") == name and share.get("status") == "ACTIVE":
                    return share
    except ClientError:
        pass
    return None


def add_sg_rule(ec2, sg_id: str, port: int, source: dict, desc: str):
    """Add a single inbound rule. Skips duplicates."""
    perm = {"IpProtocol": "tcp", "FromPort": port, "ToPort": port}
    perm.update(source)
    try:
        ec2.authorize_security_group_ingress(GroupId=sg_id, IpPermissions=[perm])
        print(f"  ✓ port {port} — {desc}")
    except ClientError as e:
        if "InvalidPermission.Duplicate" in str(e):
            print(f"  ○ port {port} — {desc} (exists)")
        else:
            print(f"  ✗ port {port} — {e}")


def get_lattice_prefix_list(ec2) -> Optional[str]:
    resp = ec2.describe_managed_prefix_lists(
        Filters=[{"Name": "prefix-list-name",
                  "Values": [f"com.amazonaws.{CONFIG['region']}.vpc-lattice"]}]
    )
    pls = resp.get("PrefixLists", [])
    return pls[0]["PrefixListId"] if pls else None


def get_vpc_cidr(ec2) -> str:
    resp = ec2.describe_vpcs(VpcIds=[CONFIG["vpc_id"]])
    return resp["Vpcs"][0].get("CidrBlock", "10.0.0.0/16")


def resolve_ami(ssm) -> str:
    resp = ssm.get_parameter(Name=CONFIG["ami_ssm_param"])
    return resp["Parameter"]["Value"]


def create_ecr_repo(ecr) -> dict:
    """Create ECR repository if it doesn't exist. Idempotent."""
    print("\n=== ECR Repository ===")
    repo_name = CONFIG["ecr_repo_name"]
    try:
        resp = ecr.describe_repositories(repositoryNames=[repo_name])
        repo = resp["repositories"][0]
        print(f"○ '{repo_name}' already exists: {repo['repositoryUri']}")
        return repo
    except ClientError as e:
        if "RepositoryNotFoundException" not in str(e):
            raise
    resp = ecr.create_repository(
        repositoryName=repo_name,
        imageScanningConfiguration={"scanOnPush": False},
        imageTagMutability="MUTABLE",
    )
    repo = resp["repository"]
    print(f"✓ Created ECR repo: {repo['repositoryUri']}")
    return repo


# ---------------------------------------------------------------------------
# Create functions
# ---------------------------------------------------------------------------

def create_security_group(ec2) -> str:
    print("\n=== Security Group ===")
    existing = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
    if existing:
        sg_id = existing["GroupId"]
        print(f"○ {CONFIG['sg_name']} already exists: {sg_id}")
    else:
        resp = ec2.create_security_group(
            GroupName=CONFIG["sg_name"],
            Description="Deadline VNC proxy - allows SSH and VNC from VPC and VPC Lattice",
            VpcId=CONFIG["vpc_id"],
        )
        sg_id = resp["GroupId"]
        ec2.create_tags(Resources=[sg_id], Tags=[{"Key": "Name", "Value": CONFIG["sg_name"]}])
        print(f"✓ Created security group: {sg_id}")

    # Add rules
    vpc_cidr = get_vpc_cidr(ec2)
    prefix_list_id = get_lattice_prefix_list(ec2)

    for port in CONFIG["ports"]:
        add_sg_rule(ec2, sg_id, port,
                    {"IpRanges": [{"CidrIp": vpc_cidr, "Description": f"port {port} from VPC"}]},
                    f"VPC CIDR {vpc_cidr}")
        if prefix_list_id:
            add_sg_rule(ec2, sg_id, port,
                        {"PrefixListIds": [{"PrefixListId": prefix_list_id,
                                            "Description": f"port {port} from VPC Lattice"}]},
                        f"VPC Lattice prefix {prefix_list_id}")

    return sg_id


def create_key_pair(ec2) -> str:
    print("\n=== SSH Key Pair ===")
    existing = find_key_pair(ec2, CONFIG["key_pair_name"])
    if existing:
        print(f"○ Key pair '{CONFIG['key_pair_name']}' already exists")
        return CONFIG["key_pair_name"]

    resp = ec2.create_key_pair(
        KeyName=CONFIG["key_pair_name"],
        KeyType="rsa",
        KeyFormat="pem",
    )
    pem = resp["KeyMaterial"]
    pem_path = f"{CONFIG['key_pair_name']}.pem"
    with open(pem_path, "w") as f:
        f.write(pem)
    import os
    os.chmod(pem_path, 0o600)
    print(f"✓ Created key pair and saved to {pem_path}")
    return CONFIG["key_pair_name"]


def create_ec2_instance(ec2, ssm_client, sg_id: str, key_name: str) -> dict:
    print("\n=== EC2 Proxy Instance ===")
    existing = find_instance_by_name(ec2, CONFIG["instance_name"])
    if existing:
        inst_id = existing["InstanceId"]
        ip = existing.get("PrivateIpAddress", "pending")
        state = existing["State"]["Name"]
        print(f"○ Instance '{CONFIG['instance_name']}' already exists: {inst_id} ({state}, {ip})")
        return existing

    ami_id = resolve_ami(ssm_client)
    print(f"  AMI: {ami_id}")

    resp = ec2.run_instances(
        ImageId=ami_id,
        InstanceType=CONFIG["instance_type"],
        KeyName=key_name,
        MinCount=1,
        MaxCount=1,
        SubnetId=CONFIG["subnet_id"],
        SecurityGroupIds=[sg_id],
        UserData=USER_DATA,
        TagSpecifications=[{
            "ResourceType": "instance",
            "Tags": [{"Key": "Name", "Value": CONFIG["instance_name"]}],
        }],
        # Enable SSM access via instance profile if available
        MetadataOptions={"HttpTokens": "required", "HttpEndpoint": "enabled"},
    )
    instance = resp["Instances"][0]
    inst_id = instance["InstanceId"]
    print(f"✓ Launched {inst_id} ({CONFIG['instance_type']})")

    # Wait for running state
    print("  Waiting for instance to be running...")
    waiter = ec2.get_waiter("instance_running")
    waiter.wait(InstanceIds=[inst_id])

    # Refresh to get private IP
    desc = ec2.describe_instances(InstanceIds=[inst_id])
    instance = desc["Reservations"][0]["Instances"][0]
    ip = instance.get("PrivateIpAddress", "unknown")
    print(f"  Private IP: {ip}")
    return instance


def create_lattice_resources(ec2, vpc_lattice, ram, sts, private_ip: str) -> dict:
    result = {}

    # --- Resource Gateway ---
    print("\n=== VPC Lattice Resource Gateway ===")
    gw = find_resource_gateway(vpc_lattice, CONFIG["resource_gateway_name"])
    if gw:
        print(f"○ '{CONFIG['resource_gateway_name']}' exists: {gw.get('id')} ({gw.get('status')})")
    else:
        # Use the same SG we created for the EC2
        sg = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
        sg_id = sg["GroupId"] if sg else CONFIG.get("security_group_id", "")
        gw = vpc_lattice.create_resource_gateway(
            name=CONFIG["resource_gateway_name"],
            vpcIdentifier=CONFIG["vpc_id"],
            subnetIds=[CONFIG["subnet_id"]],
            securityGroupIds=[sg_id],
        )
        print(f"✓ Created resource gateway: {gw.get('id')}")
    result["resource_gateway"] = gw

    # --- Resource Configuration (port 22 — SSH) ---
    print("\n=== VPC Lattice Resource Configuration ===")
    cfg = find_resource_config(vpc_lattice, CONFIG["resource_config_name"])
    if cfg:
        print(f"○ '{CONFIG['resource_config_name']}' exists: {cfg.get('id')} ({cfg.get('status')})")
    else:
        gateway_id = gw.get("id")
        cfg = vpc_lattice.create_resource_configuration(
            name=CONFIG["resource_config_name"],
            type="SINGLE",
            resourceGatewayIdentifier=gateway_id,
            portRanges=["22"],
            protocol="TCP",
            resourceConfigurationDefinition={"ipResource": {"ipAddress": private_ip}},
        )
        print(f"✓ Created resource config: {cfg.get('id')} -> {private_ip}:22")
    result["resource_config"] = cfg

    # --- RAM Share ---
    print("\n=== RAM Resource Share ===")
    share = find_ram_share(ram, CONFIG["ram_share_name"])
    resource_config_arn = cfg.get("arn")
    if share:
        print(f"○ '{CONFIG['ram_share_name']}' exists: {share.get('resourceShareArn')}")
        # Ensure resource is associated
        if resource_config_arn:
            try:
                resources = ram.list_resources(
                    resourceOwner="SELF",
                    resourceShareArns=[share["resourceShareArn"]],
                )
                existing_arns = [r["arn"] for r in resources.get("resources", [])]
                if resource_config_arn not in existing_arns:
                    ram.associate_resource_share(
                        resourceShareArn=share["resourceShareArn"],
                        resourceArns=[resource_config_arn],
                    )
                    print(f"  ✓ Associated resource config with existing share")
            except ClientError as e:
                print(f"  Warning: {e}")
    else:
        resp = ram.create_resource_share(
            name=CONFIG["ram_share_name"],
            resourceArns=[resource_config_arn],
            allowExternalPrincipals=True,
        )
        share = resp.get("resourceShare", {})
        share_arn = share.get("resourceShareArn")
        account_id = sts.get_caller_identity()["Account"]
        ram.associate_resource_share(
            resourceShareArn=share_arn,
            principals=["fleets.deadline.amazonaws.com"],
            sources=[account_id],
        )
        print(f"✓ Created RAM share: {share_arn}")
    result["ram_share"] = share

    return result


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def build_output(instance: dict, sg_id: str, lattice: dict, ecr_repo: dict) -> dict:
    cfg = lattice.get("resource_config", {})
    config_id = cfg.get("id", "")
    region = CONFIG["region"]
    endpoint = f"{config_id}.resource-endpoints.deadline.{region}.amazonaws.com" if config_id else ""
    ecr_uri = ecr_repo.get("repositoryUri", "")

    return {
        "region": region,
        "vpc_id": CONFIG["vpc_id"],
        "subnet_id": CONFIG["subnet_id"],
        "ecr": {
            "repository_name": CONFIG["ecr_repo_name"],
            "repository_uri": ecr_uri,
        },
        "ec2_instance": {
            "instance_id": instance.get("InstanceId", ""),
            "private_ip": instance.get("PrivateIpAddress", ""),
            "instance_type": CONFIG["instance_type"],
            "name": CONFIG["instance_name"],
        },
        "security_group": {
            "id": sg_id,
            "name": CONFIG["sg_name"],
        },
        "key_pair": CONFIG["key_pair_name"],
        "vpc_lattice": {
            "resource_gateway": {
                "id": lattice.get("resource_gateway", {}).get("id", ""),
                "name": CONFIG["resource_gateway_name"],
                "arn": lattice.get("resource_gateway", {}).get("arn", ""),
            },
            "resource_config": {
                "id": config_id,
                "name": CONFIG["resource_config_name"],
                "arn": cfg.get("arn", ""),
                "endpoint": endpoint,
                "port": 22,
            },
        },
        "ram_share": {
            "name": CONFIG["ram_share_name"],
            "arn": lattice.get("ram_share", {}).get("resourceShareArn", ""),
        },
        "next_steps": [
            "Add the worker SSH public key to the EC2 instance: /home/ssm-user/.ssh/authorized_keys",
            f"Attach resource config ARN to your Deadline fleet via console or CLI",
            f"Use endpoint '{endpoint}' as EC2_PROXY_HOST in the job template",
        ],
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Setup EC2 proxy + VPC Lattice for Deadline VNC access")
    parser.add_argument("--create", action="store_true", help="Create all resources")
    parser.add_argument("--output", default="gui-demo/resources.json", help="Output JSON path (default: gui-demo/resources.json)")
    args = parser.parse_args()

    ec2, vpc_lattice, ram, ssm_client, sts, ecr = get_clients()

    print("=" * 60)
    print("Deadline Cloud VNC Proxy — Infrastructure Setup")
    print("=" * 60)
    print(f"Region:  {CONFIG['region']}")
    print(f"VPC:     {CONFIG['vpc_id']}")
    print(f"Subnet:  {CONFIG['subnet_id']}")
    print(f"Mode:    {'CREATE' if args.create else 'DRY RUN (use --create to provision)'}")

    if not args.create:
        # Just show current state
        print("\n--- Current State ---")
        inst = find_instance_by_name(ec2, CONFIG["instance_name"])
        print(f"EC2 '{CONFIG['instance_name']}': {inst['InstanceId'] + ' (' + inst.get('PrivateIpAddress','') + ')' if inst else 'not found'}")
        sg = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
        print(f"SG  '{CONFIG['sg_name']}': {sg['GroupId'] if sg else 'not found'}")
        kp = find_key_pair(ec2, CONFIG["key_pair_name"])
        print(f"Key '{CONFIG['key_pair_name']}': {'exists' if kp else 'not found'}")
        gw = find_resource_gateway(vpc_lattice, CONFIG["resource_gateway_name"])
        print(f"Lattice GW '{CONFIG['resource_gateway_name']}': {gw.get('id') if gw else 'not found'}")
        cfg = find_resource_config(vpc_lattice, CONFIG["resource_config_name"])
        print(f"Lattice RC '{CONFIG['resource_config_name']}': {cfg.get('id') if cfg else 'not found'}")
        share = find_ram_share(ram, CONFIG["ram_share_name"])
        print(f"RAM Share  '{CONFIG['ram_share_name']}': {'ACTIVE' if share else 'not found'}")
        try:
            ecr.describe_repositories(repositoryNames=[CONFIG["ecr_repo_name"]])
            print(f"ECR Repo   '{CONFIG['ecr_repo_name']}': exists")
        except ClientError:
            print(f"ECR Repo   '{CONFIG['ecr_repo_name']}': not found")
        print("\nRun with --create to provision resources.")
        return

    # --- Create everything ---
    ecr_repo = create_ecr_repo(ecr)
    sg_id = create_security_group(ec2)
    key_name = create_key_pair(ec2)
    instance = create_ec2_instance(ec2, ssm_client, sg_id, key_name)
    private_ip = instance.get("PrivateIpAddress", "")

    lattice = create_lattice_resources(ec2, vpc_lattice, ram, sts, private_ip)

    # --- Write output JSON ---
    output = build_output(instance, sg_id, lattice, ecr_repo)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2, default=str)
    print(f"\n✓ Wrote resource manifest to {args.output}")

    # --- Summary ---
    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)
    cfg_id = lattice.get("resource_config", {}).get("id", "")
    endpoint = f"{cfg_id}.resource-endpoints.deadline.{CONFIG['region']}.amazonaws.com"
    print(f"""
ECR Repository: {ecr_repo.get('repositoryUri', '')}
EC2 Instance:  {instance.get('InstanceId')} ({private_ip})
Security Group: {sg_id}
VPC Lattice Endpoint: {endpoint}:22

Next steps:
  1. Add the worker's SSH public key to the EC2:
     /home/ssm-user/.ssh/authorized_keys

  2. Attach the resource config to your Deadline fleet (console or CLI):
     ARN: {lattice.get('resource_config', {}).get('arn', '')}

  3. Update job template EC2_PROXY_HOST default to:
     {endpoint}

  4. Submit a job and connect:
     aws ssm start-session --target {instance.get('InstanceId')} --region {CONFIG['region']} \\
       --document-name AWS-StartPortForwardingSession \\
       --parameters '{{"portNumber":["6080"],"localPortNumber":["6080"]}}'
     Then open http://localhost:6080/vnc.html
""")


if __name__ == "__main__":
    main()
