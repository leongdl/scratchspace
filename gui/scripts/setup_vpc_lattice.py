#!/usr/bin/env python3
"""
VPC Lattice Setup Script for Deadline Cloud SMF VNC Access

This script sets up VPC Lattice to connect SMF workers to an EC2 proxy instance.
It is IDEMPOTENT - running multiple times will not create duplicate resources.
"""

import json
import sys
from typing import TYPE_CHECKING, Optional

import boto3
from botocore.exceptions import ClientError

if TYPE_CHECKING:
    from mypy_boto3_ec2 import EC2Client
    from mypy_boto3_vpc_lattice import VPCLatticeClient
    from mypy_boto3_ram import RAMClient
    from mypy_boto3_deadline import DeadlineCloudClient

# Configuration from configure_smf_vpc.md
CONFIG = {
    "region": "us-west-2",
    "ec2_instance_id": "i-0dafdfc660885e366",
    "vpc_id": "vpc-0e8e227f1094b2f9a",
    "subnet_id": "subnet-0f145f86a08d5f76e",
    "security_group_id": "sg-09d332611399f751a",
    "farm_id": "farm-fd8e9a84d9c04142848c6ea56c9d7568",
    "fleet_id": "fleet-8eebe8e8dc07489d97e6641aab3ad6fa",
    "queue_id": "queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38",
    "ports": [22, 6080, 6688],
    # Resource names - used for idempotency checks
    "resource_gateway_name": "vnc-proxy-gateway",
    "resource_config_name": "vnc-proxy-config",
    "ram_share_name": "deadline-vnc-share",
}


def get_clients() -> tuple["EC2Client", "VPCLatticeClient", "RAMClient", "DeadlineCloudClient"]:
    """Create boto3 clients."""
    region = CONFIG["region"]
    ec2 = boto3.client("ec2", region_name=region)
    vpc_lattice = boto3.client("vpc-lattice", region_name=region)
    ram = boto3.client("ram", region_name=region)
    deadline = boto3.client("deadline", region_name=region)
    return ec2, vpc_lattice, ram, deadline


def check_security_group(ec2: "EC2Client") -> dict:
    """Check current security group rules."""
    print("\n=== Checking Security Group ===")
    response = ec2.describe_security_groups(GroupIds=[CONFIG["security_group_id"]])
    sg = response["SecurityGroups"][0]
    
    print(f"Security Group: {sg['GroupId']} ({sg.get('GroupName', 'N/A')})")
    print(f"VPC: {sg['VpcId']}")
    
    print("\nInbound Rules:")
    for rule in sg.get("IpPermissions", []):
        proto = rule.get("IpProtocol", "all")
        from_port = rule.get("FromPort", "all")
        to_port = rule.get("ToPort", "all")
        sources = []
        for ip_range in rule.get("IpRanges", []):
            sources.append(ip_range.get("CidrIp", ""))
        for sg_ref in rule.get("UserIdGroupPairs", []):
            sources.append(f"sg:{sg_ref.get('GroupId', '')}")
        for prefix in rule.get("PrefixListIds", []):
            sources.append(f"prefix:{prefix.get('PrefixListId', '')}")
        print(f"  {proto} {from_port}-{to_port} from {sources}")
    
    return sg


def add_port_rules(ec2: "EC2Client") -> None:
    """Add inbound rules for required ports. Idempotent - skips existing rules."""
    print("\n=== Adding Security Group Rules (Idempotent) ===")
    
    # Get VPC Lattice prefix list
    prefix_lists = ec2.describe_managed_prefix_lists(
        Filters=[{"Name": "prefix-list-name", "Values": [f"com.amazonaws.{CONFIG['region']}.vpc-lattice"]}]
    )
    
    prefix_list_id = None
    if prefix_lists.get("PrefixLists"):
        prefix_list_id = prefix_lists["PrefixLists"][0]["PrefixListId"]
        print(f"Found VPC Lattice prefix list: {prefix_list_id}")
    else:
        print("Warning: VPC Lattice prefix list not found")
    
    # Get VPC CIDR for tighter security rules
    vpc_response = ec2.describe_vpcs(VpcIds=[CONFIG["vpc_id"]])
    vpc_cidr = vpc_response["Vpcs"][0].get("CidrBlock", "10.0.0.0/16")
    print(f"Using VPC CIDR: {vpc_cidr}")
    
    for port in CONFIG["ports"]:
        # Add rule from VPC CIDR (for direct VPC access, e.g., testing)
        try:
            ec2.authorize_security_group_ingress(
                GroupId=CONFIG["security_group_id"],
                IpPermissions=[{
                    "IpProtocol": "tcp",
                    "FromPort": port,
                    "ToPort": port,
                    "IpRanges": [{"CidrIp": vpc_cidr, "Description": f"Allow port {port} from VPC CIDR"}]
                }]
            )
            print(f"✓ Added inbound rule for port {port} from {vpc_cidr}")
        except ClientError as e:
            if "InvalidPermission.Duplicate" in str(e):
                print(f"○ Rule for port {port} from {vpc_cidr} already exists (skipped)")
            else:
                print(f"✗ Error adding rule for port {port}: {e}")
        
        # Add rule from VPC Lattice prefix list if available
        if prefix_list_id:
            try:
                ec2.authorize_security_group_ingress(
                    GroupId=CONFIG["security_group_id"],
                    IpPermissions=[{
                        "IpProtocol": "tcp",
                        "FromPort": port,
                        "ToPort": port,
                        "PrefixListIds": [{"PrefixListId": prefix_list_id, "Description": f"Allow port {port} from VPC Lattice"}]
                    }]
                )
                print(f"✓ Added inbound rule for port {port} from VPC Lattice prefix list")
            except ClientError as e:
                if "InvalidPermission.Duplicate" in str(e):
                    print(f"○ Rule for port {port} from VPC Lattice already exists (skipped)")
                else:
                    print(f"✗ Error adding VPC Lattice rule for port {port}: {e}")


def check_vpc_and_subnet(ec2: "EC2Client") -> dict:
    """Check VPC and subnet configuration."""
    print("\n=== Checking VPC and Subnet ===")
    
    vpc_response = ec2.describe_vpcs(VpcIds=[CONFIG["vpc_id"]])
    vpc = vpc_response["Vpcs"][0]
    print(f"VPC: {vpc['VpcId']}")
    print(f"  CIDR: {vpc.get('CidrBlock', 'N/A')}")
    print(f"  State: {vpc.get('State', 'N/A')}")
    
    subnet_response = ec2.describe_subnets(SubnetIds=[CONFIG["subnet_id"]])
    subnet = subnet_response["Subnets"][0]
    print(f"\nSubnet: {subnet['SubnetId']}")
    print(f"  CIDR: {subnet.get('CidrBlock', 'N/A')}")
    print(f"  AZ: {subnet.get('AvailabilityZone', 'N/A')}")
    print(f"  Available IPs: {subnet.get('AvailableIpAddressCount', 'N/A')}")
    
    return {"vpc": vpc, "subnet": subnet}


def get_ec2_private_ip(ec2: "EC2Client") -> str:
    """Get the private IP of the EC2 instance."""
    response = ec2.describe_instances(InstanceIds=[CONFIG["ec2_instance_id"]])
    instance = response["Reservations"][0]["Instances"][0]
    private_ip = instance.get("PrivateIpAddress", "")
    print(f"\nEC2 Instance {CONFIG['ec2_instance_id']} private IP: {private_ip}")
    return private_ip


def find_existing_resource_gateway(vpc_lattice: "VPCLatticeClient") -> Optional[dict]:
    """Find existing resource gateway by name. Returns None if not found."""
    try:
        paginator = vpc_lattice.get_paginator("list_resource_gateways")
        for page in paginator.paginate():
            for gw in page.get("items", []):
                if gw.get("name") == CONFIG["resource_gateway_name"]:
                    return gw
    except ClientError as e:
        print(f"Error listing resource gateways: {e}")
    return None


def find_existing_resource_config(vpc_lattice: "VPCLatticeClient") -> Optional[dict]:
    """Find existing resource configuration by name. Returns None if not found."""
    try:
        paginator = vpc_lattice.get_paginator("list_resource_configurations")
        for page in paginator.paginate():
            for cfg in page.get("items", []):
                if cfg.get("name") == CONFIG["resource_config_name"]:
                    return cfg
    except ClientError as e:
        print(f"Error listing resource configurations: {e}")
    return None


def find_existing_ram_share(ram: "RAMClient") -> Optional[dict]:
    """Find existing RAM resource share by name. Returns None if not found."""
    try:
        paginator = ram.get_paginator("get_resource_shares")
        for page in paginator.paginate(resourceOwner="SELF"):
            for share in page.get("resourceShares", []):
                if share.get("name") == CONFIG["ram_share_name"] and share.get("status") == "ACTIVE":
                    return share
    except ClientError as e:
        print(f"Error listing RAM shares: {e}")
    return None


def list_existing_lattice_resources(vpc_lattice: "VPCLatticeClient", ram: "RAMClient") -> dict:
    """List existing VPC Lattice resources relevant to this setup."""
    print("\n=== Existing VPC Lattice Resources ===")
    
    result = {
        "resource_gateway": None,
        "resource_config": None,
        "ram_share": None,
    }
    
    # Check for existing resource gateway
    gw = find_existing_resource_gateway(vpc_lattice)
    if gw:
        print(f"\n✓ Resource Gateway found: {gw.get('name')} ({gw.get('id')})")
        print(f"  Status: {gw.get('status')}")
        print(f"  ARN: {gw.get('arn')}")
        result["resource_gateway"] = gw
    else:
        print(f"\n○ Resource Gateway '{CONFIG['resource_gateway_name']}' not found")
    
    # Check for existing resource configuration
    cfg = find_existing_resource_config(vpc_lattice)
    if cfg:
        print(f"\n✓ Resource Configuration found: {cfg.get('name')} ({cfg.get('id')})")
        print(f"  Status: {cfg.get('status')}")
        print(f"  ARN: {cfg.get('arn')}")
        result["resource_config"] = cfg
    else:
        print(f"\n○ Resource Configuration '{CONFIG['resource_config_name']}' not found")
    
    # Check for existing RAM share
    share = find_existing_ram_share(ram)
    if share:
        print(f"\n✓ RAM Share found: {share.get('name')}")
        print(f"  Status: {share.get('status')}")
        print(f"  ARN: {share.get('resourceShareArn')}")
        result["ram_share"] = share
    else:
        print(f"\n○ RAM Share '{CONFIG['ram_share_name']}' not found")
    
    return result


def create_resource_gateway(vpc_lattice: "VPCLatticeClient") -> dict:
    """Create resource gateway if it doesn't exist. Idempotent."""
    print("\n=== Creating Resource Gateway (Idempotent) ===")
    
    existing = find_existing_resource_gateway(vpc_lattice)
    if existing:
        print(f"○ Resource Gateway '{CONFIG['resource_gateway_name']}' already exists (skipped)")
        print(f"  ID: {existing.get('id')}")
        print(f"  ARN: {existing.get('arn')}")
        return existing
    
    print(f"Creating resource gateway '{CONFIG['resource_gateway_name']}'...")
    response = vpc_lattice.create_resource_gateway(
        name=CONFIG["resource_gateway_name"],
        vpcIdentifier=CONFIG["vpc_id"],
        subnetIds=[CONFIG["subnet_id"]],
        securityGroupIds=[CONFIG["security_group_id"]],
    )
    
    print(f"✓ Created resource gateway: {response.get('id')}")
    print(f"  ARN: {response.get('arn')}")
    print(f"  Status: {response.get('status')}")
    return response


def create_resource_configuration(vpc_lattice: "VPCLatticeClient", gateway_id: str, private_ip: str) -> dict:
    """Create resource configuration if it doesn't exist. Idempotent."""
    print("\n=== Creating Resource Configuration (Idempotent) ===")
    
    existing = find_existing_resource_config(vpc_lattice)
    if existing:
        print(f"○ Resource Configuration '{CONFIG['resource_config_name']}' already exists (skipped)")
        print(f"  ID: {existing.get('id')}")
        print(f"  ARN: {existing.get('arn')}")
        return existing
    
    print(f"Creating resource configuration '{CONFIG['resource_config_name']}'...")
    print(f"  Target IP: {private_ip}")
    print(f"  Port: 6688")
    
    response = vpc_lattice.create_resource_configuration(
        name=CONFIG["resource_config_name"],
        type="SINGLE",
        resourceGatewayIdentifier=gateway_id,
        portRanges=["6688"],
        protocol="TCP",
        resourceConfigurationDefinition={
            "ipResource": {"ipAddress": private_ip}
        },
    )
    
    print(f"✓ Created resource configuration: {response.get('id')}")
    print(f"  ARN: {response.get('arn')}")
    print(f"  Status: {response.get('status')}")
    return response


def create_ram_share(ram: "RAMClient", resource_config_arn: str) -> dict:
    """Create RAM resource share if it doesn't exist. Idempotent."""
    print("\n=== Creating RAM Resource Share (Idempotent) ===")
    
    existing = find_existing_ram_share(ram)
    if existing:
        print(f"○ RAM Share '{CONFIG['ram_share_name']}' already exists (skipped)")
        print(f"  ARN: {existing.get('resourceShareArn')}")
        
        # Check if resource is already associated
        try:
            resources = ram.list_resources(
                resourceOwner="SELF",
                resourceShareArns=[existing.get("resourceShareArn")]
            )
            resource_arns = [r.get("arn") for r in resources.get("resources", [])]
            if resource_config_arn in resource_arns:
                print(f"  Resource config already associated")
            else:
                print(f"  Adding resource config to existing share...")
                ram.associate_resource_share(
                    resourceShareArn=existing.get("resourceShareArn"),
                    resourceArns=[resource_config_arn]
                )
                print(f"  ✓ Associated resource config")
        except ClientError as e:
            print(f"  Warning checking/associating resources: {e}")
        
        return existing
    
    print(f"Creating RAM share '{CONFIG['ram_share_name']}'...")
    # First create the share with the resource
    response = ram.create_resource_share(
        name=CONFIG["ram_share_name"],
        resourceArns=[resource_config_arn],
        allowExternalPrincipals=True,
    )
    
    share = response.get("resourceShare", {})
    share_arn = share.get("resourceShareArn")
    
    # Get account ID for sources parameter
    sts = boto3.client("sts", region_name=CONFIG["region"])
    account_id = sts.get_caller_identity()["Account"]
    
    # Associate the Deadline Cloud service principal with account as source
    print(f"  Associating Deadline Cloud service principal (source: {account_id})...")
    ram.associate_resource_share(
        resourceShareArn=share_arn,
        principals=["fleets.deadline.amazonaws.com"],
        sources=[account_id],
    )
    
    share = response.get("resourceShare", {})
    print(f"✓ Created RAM share: {share.get('name')}")
    print(f"  ARN: {share.get('resourceShareArn')}")
    print(f"  Status: {share.get('status')}")
    return share


def update_deadline_fleet(deadline: "DeadlineCloudClient", resource_config_arn: str) -> None:
    """Update Deadline fleet with VPC resource endpoint."""
    print("\n=== Updating Deadline Fleet ===")
    
    # First get current fleet config to preserve other settings
    try:
        fleet = deadline.get_fleet(
            farmId=CONFIG["farm_id"],
            fleetId=CONFIG["fleet_id"]
        )
        print(f"Fleet: {fleet.get('displayName', CONFIG['fleet_id'])}")
        print(f"Status: {fleet.get('status')}")
        
        current_config = fleet.get("configuration", {})
        smf_config = current_config.get("serviceManagedEc2", {})
        vpc_config = smf_config.get("vpcConfiguration", {})
        current_arns = vpc_config.get("resourceConfigurationArns", [])
        
        if resource_config_arn in current_arns:
            print(f"○ Resource config already attached to fleet (skipped)")
            return
        
        print(f"Current VPC resource ARNs: {current_arns}")
        
    except ClientError as e:
        print(f"Error getting fleet: {e}")
        print("\nTo manually update the fleet, run:")
        print(f"""
aws deadline update-fleet \\
    --farm-id {CONFIG['farm_id']} \\
    --fleet-id {CONFIG['fleet_id']} \\
    --configuration '{{"serviceManagedEc2":{{"vpcConfiguration":{{"resourceConfigurationArns":["{resource_config_arn}"]}}}}}}' \\
    --region {CONFIG['region']}
""")
        return
    
    # Update fleet with new resource config
    new_arns = list(set(current_arns + [resource_config_arn]))
    
    try:
        deadline.update_fleet(
            farmId=CONFIG["farm_id"],
            fleetId=CONFIG["fleet_id"],
            configuration={
                "serviceManagedEc2": {
                    "vpcConfiguration": {
                        "resourceConfigurationArns": new_arns
                    }
                }
            }
        )
        print(f"✓ Updated fleet with resource config")
        print(f"  New VPC resource ARNs: {new_arns}")
    except ClientError as e:
        print(f"✗ Error updating fleet: {e}")
        print("\nYou may need to update via console or ensure the resource config is ACTIVE first.")


def print_summary(existing: dict, resource_config_arn: Optional[str] = None) -> None:
    """Print summary and next steps."""
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    if existing.get("resource_gateway"):
        gw = existing["resource_gateway"]
        print(f"\nResource Gateway: {gw.get('name')} ({gw.get('status')})")
    
    if existing.get("resource_config"):
        cfg = existing["resource_config"]
        config_id = cfg.get("id", "")
        print(f"Resource Configuration: {cfg.get('name')} ({cfg.get('status')})")
        print(f"\nWorker endpoint:")
        print(f"  {config_id}.resource-endpoints.deadline.{CONFIG['region']}.amazonaws.com:6688")
    
    if existing.get("ram_share"):
        share = existing["ram_share"]
        print(f"\nRAM Share: {share.get('name')} ({share.get('status')})")
    
    print("\n" + "=" * 60)
    print("USAGE")
    print("=" * 60)
    print("""
Run modes:
  python setup_vpc_lattice.py              # Check current state only
  python setup_vpc_lattice.py --add-rules  # Add security group rules
  python setup_vpc_lattice.py --create     # Create all VPC Lattice resources
  python setup_vpc_lattice.py --full       # Add rules + create resources + update fleet

All operations are IDEMPOTENT - safe to run multiple times.
""")


def main() -> None:
    """Main entry point."""
    print("VPC Lattice Setup for Deadline Cloud SMF")
    print("=" * 50)
    print("This script is IDEMPOTENT - safe to run multiple times")
    
    ec2, vpc_lattice, ram, deadline = get_clients()
    
    # Always check current state
    check_security_group(ec2)
    check_vpc_and_subnet(ec2)
    private_ip = get_ec2_private_ip(ec2)
    existing = list_existing_lattice_resources(vpc_lattice, ram)
    
    # Add security group rules if requested
    if "--add-rules" in sys.argv or "--full" in sys.argv:
        add_port_rules(ec2)
        print("\n=== Updated Security Group ===")
        check_security_group(ec2)
    
    # Create VPC Lattice resources if requested
    resource_config_arn = None
    if "--create" in sys.argv or "--full" in sys.argv:
        # Create resource gateway
        gw = create_resource_gateway(vpc_lattice)
        gateway_id = gw.get("id")
        existing["resource_gateway"] = gw
        
        # Create resource configuration
        cfg = create_resource_configuration(vpc_lattice, gateway_id, private_ip)
        resource_config_arn = cfg.get("arn")
        existing["resource_config"] = cfg
        
        # Create RAM share
        if resource_config_arn:
            share = create_ram_share(ram, resource_config_arn)
            existing["ram_share"] = share
    
    # Update Deadline fleet if requested
    if "--full" in sys.argv:
        if resource_config_arn or existing.get("resource_config"):
            arn = resource_config_arn or existing["resource_config"].get("arn")
            if arn:
                update_deadline_fleet(deadline, arn)
    
    # Print summary
    print_summary(existing, resource_config_arn)


if __name__ == "__main__":
    main()
