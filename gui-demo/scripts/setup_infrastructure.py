#!/usr/bin/env python3
"""
Infrastructure Setup for Deadline Cloud SMF VNC Access

Creates:
  1. Security group for the EC2 proxy bastion
  2. SSH key pair for the reverse tunnel
  3. EC2 T3 instance with user-data that configures GatewayPorts + sshd
  4. VPC Lattice resource gateway + resource configuration (port 22)
  5. RAM share with fleets.deadline.amazonaws.com
  6. FSx for Lustre filesystem (PERSISTENT_2, 1200 GB, 125 MB/s/TiB, no backups)
  7. VPC Interface Endpoint for FSx
  8. VPC Interface Endpoint for SSM (bastion access)

Outputs a JSON file with all resource IDs/ARNs so the job template can reference them.
Resources not yet created are represented as null in the output.

Idempotent — safe to run multiple times. Finds existing resources by Name tag / name field.
Dry run (no --create) checks current state and writes the JSON with whatever exists.

Usage:
  python3 setup_infrastructure.py                # Dry run — show what exists, write JSON
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
    # Ports exposed through the security group (2049 = NFS for OpenZFS)
    "ports": [22, 2049, 6080, 8188],
    # ECR
    "ecr_repo_name": "desktop-demo",
    # FSx for OpenZFS
    "fsx_name": "deadline-shared-fs",
    "fsx_storage_gb": 64,
    "fsx_deployment_type": "SINGLE_AZ_1",
    "fsx_throughput_mbps": 64,
    "fsx_vpce_name": "deadline-fsx-vpce",
    "fsx_vpce_service": "com.amazonaws.us-west-2.fsx",
    "bastion_vpce_name": "deadline-ssm-vpce",
    "bastion_vpce_service": "com.amazonaws.us-west-2.ssm",
    "ssmmessages_vpce_name": "deadline-ssmmessages-vpce",
    "ssmmessages_vpce_service": "com.amazonaws.us-west-2.ssmmessages",
    "ec2messages_vpce_name": "deadline-ec2messages-vpce",
    "ec2messages_vpce_service": "com.amazonaws.us-west-2.ec2messages",
}

# ---------------------------------------------------------------------------
# User-data script — runs once on first boot
# ---------------------------------------------------------------------------
USER_DATA = textwrap.dedent("""\
    #!/bin/bash
    set -e

    # --- SSH reverse-tunnel support ---
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
# Helpers — clients
# ---------------------------------------------------------------------------

def get_clients():
    region = CONFIG["region"]
    return (
        boto3.client("ec2",         region_name=region),
        boto3.client("vpc-lattice", region_name=region),
        boto3.client("ram",         region_name=region),
        boto3.client("ssm",         region_name=region),
        boto3.client("sts",         region_name=region),
        boto3.client("ecr",         region_name=region),
        boto3.client("fsx",         region_name=region),
    )


# ---------------------------------------------------------------------------
# Helpers — find existing resources (all return None if not found)
# ---------------------------------------------------------------------------

def find_instance_by_name(ec2, name: str) -> Optional[dict]:
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
            {"Name": "vpc-id",     "Values": [vpc_id]},
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


def find_fsx_filesystem(fsx, name: str) -> Optional[dict]:
    """Find an FSx filesystem by Name tag, ignoring DELETING/FAILED."""
    try:
        for page in fsx.get_paginator("describe_file_systems").paginate():
            for fs in page.get("FileSystems", []):
                if fs.get("Lifecycle") in ("DELETING", "FAILED"):
                    continue
                tags = {t["Key"]: t["Value"] for t in fs.get("Tags", [])}
                if tags.get("Name") == name:
                    return fs
    except ClientError:
        pass
    return None


def find_vpc_endpoint(ec2, name: str, vpc_id: str) -> Optional[dict]:
    """Find a VPC Interface endpoint by Name tag."""
    resp = ec2.describe_vpc_endpoints(
        Filters=[
            {"Name": "tag:Name",             "Values": [name]},
            {"Name": "vpc-id",               "Values": [vpc_id]},
            {"Name": "vpc-endpoint-state",   "Values": ["pending", "available"]},
        ]
    )
    eps = resp.get("VpcEndpoints", [])
    return eps[0] if eps else None


def find_ecr_repo(ecr, name: str) -> Optional[dict]:
    try:
        resp = ecr.describe_repositories(repositoryNames=[name])
        return resp["repositories"][0]
    except ClientError as e:
        if "RepositoryNotFoundException" in str(e):
            return None
        raise


# ---------------------------------------------------------------------------
# Helpers — misc
# ---------------------------------------------------------------------------

def add_sg_rule(ec2, sg_id: str, port: int, source: dict, desc: str):
    """Add a single inbound rule. Skips duplicates silently."""
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


def _vpce_dns(vpce: dict) -> str:
    """Return the first private DNS name from a VPC endpoint, or empty string."""
    for entry in vpce.get("DnsEntries", []):
        dns = entry.get("DnsName", "")
        if dns:
            return dns
    return ""


# ---------------------------------------------------------------------------
# Create functions — all idempotent
# ---------------------------------------------------------------------------

def create_ecr_repo(ecr) -> Optional[dict]:
    print("\n=== ECR Repository ===")
    existing = find_ecr_repo(ecr, CONFIG["ecr_repo_name"])
    if existing:
        print(f"○ '{CONFIG['ecr_repo_name']}' already exists: {existing['repositoryUri']}")
        return existing
    resp = ecr.create_repository(
        repositoryName=CONFIG["ecr_repo_name"],
        imageScanningConfiguration={"scanOnPush": False},
        imageTagMutability="MUTABLE",
    )
    repo = resp["repository"]
    print(f"✓ Created ECR repo: {repo['repositoryUri']}")
    return repo


def create_security_group(ec2) -> str:
    print("\n=== Security Group ===")
    existing = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
    if existing:
        sg_id = existing["GroupId"]
        print(f"○ {CONFIG['sg_name']} already exists: {sg_id}")
    else:
        resp = ec2.create_security_group(
            GroupName=CONFIG["sg_name"],
            Description="Deadline VNC proxy — SSH, VNC, Lustre from VPC and VPC Lattice",
            VpcId=CONFIG["vpc_id"],
        )
        sg_id = resp["GroupId"]
        ec2.create_tags(Resources=[sg_id], Tags=[{"Key": "Name", "Value": CONFIG["sg_name"]}])
        print(f"✓ Created security group: {sg_id}")

    vpc_cidr = get_vpc_cidr(ec2)
    prefix_list_id = get_lattice_prefix_list(ec2)

    for port in CONFIG["ports"]:
        add_sg_rule(ec2, sg_id, port,
                    {"IpRanges": [{"CidrIp": vpc_cidr, "Description": f"port {port} from VPC"}]},
                    f"VPC CIDR {vpc_cidr}")
        # Lustre (988) doesn't need a Lattice rule
        if prefix_list_id and port != 988:
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


def ensure_instance_profile(ec2, instance_id: str):
    """Attach SSMManagedEC2Role profile if not already attached."""
    resp = ec2.describe_iam_instance_profile_associations(
        Filters=[{"Name": "instance-id", "Values": [instance_id]}]
    )
    assocs = resp.get("IamInstanceProfileAssociations", [])
    active = [a for a in assocs if a["State"] in ("associated", "associating")]
    if active:
        print(f"  ○ Instance profile already attached: {active[0]['IamInstanceProfile']['Arn']}")
        return
    ec2.associate_iam_instance_profile(
        InstanceId=instance_id,
        IamInstanceProfile={"Name": "SSMManagedEC2Role"},
    )
    print(f"  ✓ Attached SSMManagedEC2Role to {instance_id}")
    print("\n=== EC2 Proxy Instance ===")
    existing = find_instance_by_name(ec2, CONFIG["instance_name"])
    if existing:
        inst_id = existing["InstanceId"]
        ip    = existing.get("PrivateIpAddress", "pending")
        state = existing["State"]["Name"]
        print(f"○ '{CONFIG['instance_name']}' already exists: {inst_id} ({state}, {ip})")
        ensure_instance_profile(ec2, inst_id)
        return existing

    ami_id = resolve_ami(ssm_client)
    print(f"  AMI: {ami_id}")

    launch_params = dict(
        ImageId=ami_id,
        InstanceType=CONFIG["instance_type"],
        MinCount=1, MaxCount=1,
        SubnetId=CONFIG["subnet_id"],
        SecurityGroupIds=[sg_id],
        UserData=USER_DATA,
        IamInstanceProfile={"Name": "SSMManagedEC2Role"},
        TagSpecifications=[{
            "ResourceType": "instance",
            "Tags": [{"Key": "Name", "Value": CONFIG["instance_name"]}],
        }],
        MetadataOptions={"HttpTokens": "required", "HttpEndpoint": "enabled"},
    )
    if key_name:
        launch_params["KeyName"] = key_name

    resp = ec2.run_instances(**launch_params)
    instance = resp["Instances"][0]
    inst_id = instance["InstanceId"]
    print(f"✓ Launched {inst_id} ({CONFIG['instance_type']})")

    print("  Waiting for instance to be running...")
    ec2.get_waiter("instance_running").wait(InstanceIds=[inst_id])

    desc = ec2.describe_instances(InstanceIds=[inst_id])
    instance = desc["Reservations"][0]["Instances"][0]
    print(f"  Private IP: {instance.get('PrivateIpAddress', 'unknown')}")
    ensure_instance_profile(ec2, inst_id)
    return instance


def create_lattice_resources(ec2, vpc_lattice, ram, sts, private_ip: str) -> dict:
    result = {}

    # --- Resource Gateway ---
    print("\n=== VPC Lattice Resource Gateway ===")
    gw = find_resource_gateway(vpc_lattice, CONFIG["resource_gateway_name"])
    if gw:
        print(f"○ '{CONFIG['resource_gateway_name']}' exists: {gw.get('id')} ({gw.get('status')})")
    else:
        sg = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
        sg_id = sg["GroupId"] if sg else ""
        gw = vpc_lattice.create_resource_gateway(
            name=CONFIG["resource_gateway_name"],
            vpcIdentifier=CONFIG["vpc_id"],
            subnetIds=[CONFIG["subnet_id"]],
            securityGroupIds=[sg_id],
        )
        print(f"✓ Created resource gateway: {gw.get('id')}")
    result["resource_gateway"] = gw

    # --- Resource Configuration ---
    print("\n=== VPC Lattice Resource Configuration ===")
    cfg = find_resource_config(vpc_lattice, CONFIG["resource_config_name"])
    if cfg:
        print(f"○ '{CONFIG['resource_config_name']}' exists: {cfg.get('id')} ({cfg.get('status')})")
    else:
        cfg = vpc_lattice.create_resource_configuration(
            name=CONFIG["resource_config_name"],
            type="SINGLE",
            resourceGatewayIdentifier=gw.get("id"),
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
                    print("  ✓ Associated resource config with existing share")
            except ClientError as e:
                print(f"  Warning: {e}")
    else:
        resp = ram.create_resource_share(
            name=CONFIG["ram_share_name"],
            resourceArns=[resource_config_arn],
            allowExternalPrincipals=True,
        )
        share = resp.get("resourceShare", {})
        account_id = sts.get_caller_identity()["Account"]
        ram.associate_resource_share(
            resourceShareArn=share["resourceShareArn"],
            principals=["fleets.deadline.amazonaws.com"],
            sources=[account_id],
        )
        print(f"✓ Created RAM share: {share.get('resourceShareArn')}")
    result["ram_share"] = share

    return result


def create_fsx_filesystem(fsx, ec2) -> dict:
    print("\n=== FSx for OpenZFS ===")
    existing = find_fsx_filesystem(fsx, CONFIG["fsx_name"])
    if existing:
        fs_id = existing["FileSystemId"]
        print(f"○ '{CONFIG['fsx_name']}' already exists: {fs_id} ({existing['Lifecycle']})")
        return existing

    sg = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
    sg_id = sg["GroupId"] if sg else ""

    resp = fsx.create_file_system(
        FileSystemType="OPENZFS",
        StorageCapacity=CONFIG["fsx_storage_gb"],
        StorageType="SSD",
        SubnetIds=[CONFIG["subnet_id"]],
        SecurityGroupIds=[sg_id],
        Tags=[{"Key": "Name", "Value": CONFIG["fsx_name"]}],
        OpenZFSConfiguration={
            "DeploymentType": CONFIG["fsx_deployment_type"],
            "ThroughputCapacity": CONFIG["fsx_throughput_mbps"],
            "AutomaticBackupRetentionDays": 0,  # no backups
            "CopyTagsToBackups": False,
            "CopyTagsToVolumes": False,
            "RootVolumeConfiguration": {
                "DataCompressionType": "LZ4",
                "NfsExports": [{
                    "ClientConfigurations": [{
                        "Clients": "*",
                        "Options": ["rw", "crossmnt", "no_root_squash"],
                    }]
                }],
            },
        },
    )
    fs = resp["FileSystem"]
    print(f"✓ Created FSx OpenZFS: {fs['FileSystemId']} (status: {fs['Lifecycle']}, ~3 min to become available)")
    return fs


def get_fsx_nfs_ip(fsx, ec2, fs_id: str) -> Optional[str]:
    """Wait for filesystem to be AVAILABLE and return its private IP via ENI lookup."""
    print(f"  Waiting for FSx {fs_id} to be AVAILABLE...")
    for _ in range(30):  # up to ~5 min
        resp = fsx.describe_file_systems(FileSystemIds=[fs_id])
        fs = resp["FileSystems"][0]
        if fs["Lifecycle"] == "AVAILABLE":
            eni_ids = fs.get("NetworkInterfaceIds", [])
            if eni_ids:
                eni = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_ids[0]])
                ip = eni["NetworkInterfaces"][0]["PrivateIpAddress"]
                print(f"  FSx AVAILABLE — private IP: {ip}")
                return ip
        print(f"  Status: {fs['Lifecycle']}, waiting 10s...")
        time.sleep(10)
    return None


def update_lattice_fsx_config(vpc_lattice, fsx_ip: str):
    """Update the existing FSx Lattice resource config to point at the new filesystem IP."""
    print("\n=== Updating VPC Lattice FSx Resource Config ===")
    cfg_id = "rcfg-072853a357ca69135"
    try:
        vpc_lattice.update_resource_configuration(
            resourceConfigurationIdentifier=cfg_id,
            resourceConfigurationDefinition={"ipResource": {"ipAddress": fsx_ip}},
        )
        print(f"✓ Updated {cfg_id} → {fsx_ip}")
    except ClientError as e:
        print(f"  Warning updating Lattice config: {e}")


def create_vpc_endpoint(ec2, vpce_name: str, service_name: str, label: str) -> dict:
    """Create an Interface VPC endpoint. Idempotent."""
    print(f"\n=== VPC Endpoint — {label} ===")
    existing = find_vpc_endpoint(ec2, vpce_name, CONFIG["vpc_id"])
    if existing:
        ep_id = existing["VpcEndpointId"]
        print(f"○ '{vpce_name}' already exists: {ep_id} ({existing['State']})")
        return existing

    sg = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
    sg_id = sg["GroupId"] if sg else ""

    resp = ec2.create_vpc_endpoint(
        VpcEndpointType="Interface",
        VpcId=CONFIG["vpc_id"],
        ServiceName=service_name,
        SubnetIds=[CONFIG["subnet_id"]],
        SecurityGroupIds=[sg_id],
        PrivateDnsEnabled=True,
        TagSpecifications=[{
            "ResourceType": "vpc-endpoint",
            "Tags": [{"Key": "Name", "Value": vpce_name}],
        }],
    )
    ep = resp["VpcEndpoint"]
    print(f"✓ Created VPC endpoint: {ep['VpcEndpointId']}")
    return ep


# ---------------------------------------------------------------------------
# Output builder — null-safe, works for both dry-run and create
# ---------------------------------------------------------------------------

def _fsx_mount_info(fs: Optional[dict]) -> dict:
    if not fs:
        return {"filesystem_id": None, "dns_name": None, "mount_path": None,
                "mount_command": None, "lifecycle": None}
    fs_id = fs.get("FileSystemId", "")
    dns   = fs.get("DNSName", "")
    path  = "/mnt/fsx"
    cmd   = f"mount -t nfs -o nfsvers=4.1 {dns}:/ {path}" if dns else None
    return {
        "filesystem_id": fs_id or None,
        "dns_name":      dns  or None,
        "mount_path":    path,
        "mount_command": cmd,
        "lifecycle":     fs.get("Lifecycle"),
        "type":          "OPENZFS",
    }


def build_output(
    instance:    Optional[dict],
    sg_id:       Optional[str],
    lattice:     dict,
    ecr_repo:    Optional[dict],
    fsx_fs:      Optional[dict],
    vpce_fsx:    Optional[dict],
    vpce_bastion: Optional[dict],
) -> dict:
    cfg        = lattice.get("resource_config") or {}
    config_id  = cfg.get("id", "")
    region     = CONFIG["region"]
    endpoint   = (f"{config_id}.resource-endpoints.deadline.{region}.amazonaws.com"
                  if config_id else None)

    inst_id    = instance.get("InstanceId")    if instance else None
    private_ip = instance.get("PrivateIpAddress") if instance else None

    return {
        "region":    region,
        "vpc_id":    CONFIG["vpc_id"],
        "subnet_id": CONFIG["subnet_id"],

        "ecr": {
            "repository_name": CONFIG["ecr_repo_name"],
            "repository_uri":  ecr_repo.get("repositoryUri") if ecr_repo else None,
        },

        "ec2_instance": {
            "instance_id":       inst_id,
            "private_ip":        private_ip,
            "instance_type":     CONFIG["instance_type"],
            "name":              CONFIG["instance_name"],
            "ssm_session_command": (
                f"aws ssm start-session --target {inst_id} --region {region}"
                if inst_id else None
            ),
        },

        "security_group": {
            "id":   sg_id,
            "name": CONFIG["sg_name"],
        },

        "key_pair": CONFIG["key_pair_name"],

        "vpc_lattice": {
            "resource_gateway": {
                "id":   lattice.get("resource_gateway", {}).get("id")   if lattice.get("resource_gateway") else None,
                "name": CONFIG["resource_gateway_name"],
                "arn":  lattice.get("resource_gateway", {}).get("arn")  if lattice.get("resource_gateway") else None,
            },
            "resource_config": {
                "id":       config_id or None,
                "name":     CONFIG["resource_config_name"],
                "arn":      cfg.get("arn") or None,
                "endpoint": endpoint,
                "port":     22,
            },
        },

        "ram_share": {
            "name": CONFIG["ram_share_name"],
            "arn":  lattice.get("ram_share", {}).get("resourceShareArn") if lattice.get("ram_share") else None,
        },

        "fsx": _fsx_mount_info(fsx_fs),

        "vpc_endpoints": {
            "fsx": {
                "id":    vpce_fsx.get("VpcEndpointId") if vpce_fsx else None,
                "name":  CONFIG["fsx_vpce_name"],
                "state": vpce_fsx.get("State")         if vpce_fsx else None,
                "dns":   _vpce_dns(vpce_fsx)           if vpce_fsx else None,
            },
            "bastion_ssm": {
                "id":    vpce_bastion.get("VpcEndpointId") if vpce_bastion else None,
                "name":  CONFIG["bastion_vpce_name"],
                "state": vpce_bastion.get("State")         if vpce_bastion else None,
                "dns":   _vpce_dns(vpce_bastion)           if vpce_bastion else None,
            },
        },

        "next_steps": [
            "Add the worker SSH public key to the EC2: /home/ssm-user/.ssh/authorized_keys",
            f"Attach resource config ARN to your Deadline fleet via console or CLI",
            f"Use endpoint '{endpoint}' as EC2_PROXY_HOST in the job template" if endpoint else "Create resources with --create first",
            f"Mount FSx on workers: {_fsx_mount_info(fsx_fs)['mount_command']}" if fsx_fs else "FSx not yet created",
        ],
    }


# ---------------------------------------------------------------------------
# State check — used by both dry-run and after create
# ---------------------------------------------------------------------------

def check_state(ec2, vpc_lattice, ram, ecr, fsx) -> dict:
    """Query all resources and return a state dict (values are resource dicts or None)."""
    inst  = find_instance_by_name(ec2, CONFIG["instance_name"])
    sg    = find_sg_by_name(ec2, CONFIG["sg_name"], CONFIG["vpc_id"])
    kp    = find_key_pair(ec2, CONFIG["key_pair_name"])
    gw    = find_resource_gateway(vpc_lattice, CONFIG["resource_gateway_name"])
    cfg   = find_resource_config(vpc_lattice, CONFIG["resource_config_name"])
    share = find_ram_share(ram, CONFIG["ram_share_name"])
    repo  = find_ecr_repo(ecr, CONFIG["ecr_repo_name"])
    fs    = find_fsx_filesystem(fsx, CONFIG["fsx_name"])
    vpce_fsx     = find_vpc_endpoint(ec2, CONFIG["fsx_vpce_name"],          CONFIG["vpc_id"])
    vpce_bastion = find_vpc_endpoint(ec2, CONFIG["bastion_vpce_name"],      CONFIG["vpc_id"])
    vpce_ssmmsg  = find_vpc_endpoint(ec2, CONFIG["ssmmessages_vpce_name"],  CONFIG["vpc_id"])
    vpce_ec2msg  = find_vpc_endpoint(ec2, CONFIG["ec2messages_vpce_name"],  CONFIG["vpc_id"])

    return dict(
        instance=inst, sg=sg, key_pair=kp,
        resource_gateway=gw, resource_config=cfg, ram_share=share,
        ecr_repo=repo, fsx_fs=fs,
        vpce_fsx=vpce_fsx, vpce_bastion=vpce_bastion,
        vpce_ssmmsg=vpce_ssmmsg, vpce_ec2msg=vpce_ec2msg,
    )


def print_state(state: dict):
    inst         = state["instance"]
    sg           = state["sg"]
    kp           = state["key_pair"]
    gw           = state["resource_gateway"]
    cfg          = state["resource_config"]
    share        = state["ram_share"]
    repo         = state["ecr_repo"]
    fs           = state["fsx_fs"]
    vpce_fsx     = state["vpce_fsx"]
    vpce_bastion = state["vpce_bastion"]

    def _s(v, label): return f"{label}: {v}" if v else "not found"

    print(f"\n{'─'*60}")
    print(f"EC2 '{CONFIG['instance_name']}':        "
          + (f"{inst['InstanceId']} ({inst.get('PrivateIpAddress','')}, {inst['State']['Name']})" if inst else "not found"))
    print(f"SG  '{CONFIG['sg_name']}':  "
          + (sg["GroupId"] if sg else "not found"))
    print(f"Key '{CONFIG['key_pair_name']}':  "
          + ("exists" if kp else "not found"))
    print(f"Lattice GW '{CONFIG['resource_gateway_name']}':  "
          + (f"{gw.get('id')} ({gw.get('status')})" if gw else "not found"))
    print(f"Lattice RC '{CONFIG['resource_config_name']}':  "
          + (f"{cfg.get('id')} ({cfg.get('status')})" if cfg else "not found"))
    print(f"RAM Share  '{CONFIG['ram_share_name']}':  "
          + ("ACTIVE" if share else "not found"))
    print(f"ECR Repo   '{CONFIG['ecr_repo_name']}':  "
          + (repo.get("repositoryUri", "exists") if repo else "not found"))
    print(f"FSx        '{CONFIG['fsx_name']}':  "
          + (f"{fs['FileSystemId']} ({fs['Lifecycle']})" if fs else "not found"))
    print(f"VPCE FSx   '{CONFIG['fsx_vpce_name']}':  "
          + (f"{vpce_fsx['VpcEndpointId']} ({vpce_fsx['State']})" if vpce_fsx else "not found"))
    print(f"VPCE SSM   '{CONFIG['bastion_vpce_name']}':  "
          + (f"{vpce_bastion['VpcEndpointId']} ({vpce_bastion['State']})" if vpce_bastion else "not found"))
    print(f"{'─'*60}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Setup EC2 proxy + VPC Lattice + FSx for Deadline VNC access")
    parser.add_argument("--create",   action="store_true", help="Create all resources")
    parser.add_argument("--output",   default="gui-demo/resources.json", help="Output JSON path")
    parser.add_argument("--key-pair", action="store_true", default=False,
                        help="Create an SSH key pair (default: use SSM instead)")
    args = parser.parse_args()

    ec2, vpc_lattice, ram, ssm_client, sts, ecr, fsx = get_clients()

    print("=" * 60)
    print("Deadline Cloud VNC Proxy — Infrastructure Setup")
    print("=" * 60)
    print(f"Region:  {CONFIG['region']}")
    print(f"VPC:     {CONFIG['vpc_id']}")
    print(f"Subnet:  {CONFIG['subnet_id']}")
    print(f"Mode:    {'CREATE' if args.create else 'DRY RUN (use --create to provision)'}")

    if not args.create:
        print("\n--- Current State ---")
        state = check_state(ec2, vpc_lattice, ram, ecr, fsx)
        print_state(state)

        # Build lattice dict from found resources for output
        lattice = {
            "resource_gateway": state["resource_gateway"],
            "resource_config":  state["resource_config"],
            "ram_share":        state["ram_share"],
        }
        output = build_output(
            instance=state["instance"],
            sg_id=state["sg"]["GroupId"] if state["sg"] else None,
            lattice=lattice,
            ecr_repo=state["ecr_repo"],
            fsx_fs=state["fsx_fs"],
            vpce_fsx=state["vpce_fsx"],
            vpce_bastion=state["vpce_bastion"],
        )
        with open(args.output, "w") as f:
            json.dump(output, f, indent=2, default=str)
        print(f"\n✓ Wrote current state to {args.output} (null = not yet created)")
        print("Run with --create to provision missing resources.")
        return

    # --- Create everything ---
    ecr_repo = create_ecr_repo(ecr)
    sg_id    = create_security_group(ec2)

    key_name = None
    if args.key_pair:
        key_name = create_key_pair(ec2)
    else:
        print("\n=== SSH Key Pair ===")
        print("○ Skipped (using SSM access). Pass --key-pair to create one.")

    instance   = create_ec2_instance(ec2, ssm_client, sg_id, key_name)
    private_ip = instance.get("PrivateIpAddress", "")

    lattice      = create_lattice_resources(ec2, vpc_lattice, ram, sts, private_ip)
    fsx_fs       = create_fsx_filesystem(fsx, ec2)
    # Wait for AVAILABLE and update the Lattice config to point at the new filesystem
    if fsx_fs and fsx_fs.get("Lifecycle") != "AVAILABLE":
        fsx_ip = get_fsx_nfs_ip(fsx, ec2, fsx_fs["FileSystemId"])
    else:
        # Already available — look up IP from ENI
        eni_ids = fsx_fs.get("NetworkInterfaceIds", []) if fsx_fs else []
        if eni_ids:
            eni = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_ids[0]])
            fsx_ip = eni["NetworkInterfaces"][0]["PrivateIpAddress"]
        else:
            fsx_ip = None
    if fsx_ip:
        update_lattice_fsx_config(vpc_lattice, fsx_ip)
    vpce_fsx     = create_vpc_endpoint(ec2, CONFIG["fsx_vpce_name"],          CONFIG["fsx_vpce_service"],          "FSx")
    vpce_bastion = create_vpc_endpoint(ec2, CONFIG["bastion_vpce_name"],      CONFIG["bastion_vpce_service"],      "SSM / Bastion")
    create_vpc_endpoint(ec2, CONFIG["ssmmessages_vpce_name"], CONFIG["ssmmessages_vpce_service"], "SSM Messages")
    create_vpc_endpoint(ec2, CONFIG["ec2messages_vpce_name"], CONFIG["ec2messages_vpce_service"], "EC2 Messages")

    output = build_output(
        instance=instance,
        sg_id=sg_id,
        lattice=lattice,
        ecr_repo=ecr_repo,
        fsx_fs=fsx_fs,
        vpce_fsx=vpce_fsx,
        vpce_bastion=vpce_bastion,
    )
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2, default=str)
    print(f"\n✓ Wrote resource manifest to {args.output}")

    # --- Summary ---
    cfg_id   = lattice.get("resource_config", {}).get("id", "")
    endpoint = f"{cfg_id}.resource-endpoints.deadline.{CONFIG['region']}.amazonaws.com" if cfg_id else "pending"
    fsx_info = _fsx_mount_info(fsx_fs)

    print(f"""
{'='*60}
DONE
{'='*60}
ECR Repository:       {ecr_repo.get('repositoryUri', '')}
EC2 Instance:         {instance.get('InstanceId')} ({private_ip})
Security Group:       {sg_id}
VPC Lattice Endpoint: {endpoint}:22
FSx OpenZFS:          {fsx_fs.get('FileSystemId') if fsx_fs else 'n/a'} ({fsx_fs.get('Lifecycle') if fsx_fs else 'n/a'})
FSx Mount Command:    {fsx_info['mount_command']}
VPCE FSx:             {vpce_fsx.get('VpcEndpointId')}
VPCE SSM:             {vpce_bastion.get('VpcEndpointId')}

Next steps:
  1. Add the worker SSH public key to the EC2:
     /home/ssm-user/.ssh/authorized_keys

  2. Attach the resource config to your Deadline fleet:
     ARN: {lattice.get('resource_config', {}).get('arn', '')}

  3. Update job template EC2_PROXY_HOST to:
     {endpoint}

  4. Mount FSx on workers (once filesystem is AVAILABLE):
     {fsx_info['mount_command']}
""")


if __name__ == "__main__":
    main()
