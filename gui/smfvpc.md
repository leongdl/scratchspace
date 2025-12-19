With Amazon VPC resource endpoints for Deadline Cloud service-managed fleets (SMF), you can connect your VPC resources such as network file systems (NFS), license servers, and databases with your Deadline Cloud workers. This feature lets you leverage Deadline Cloud's fully managed platform while integrating with your existing infrastructure within a VPC.

A diagram showing how the Deadline Cloud SMF connects with the VPC Lattice.

How VPC resource endpoints work

VPC resource endpoints use VPC Lattice to create a secure connection between your Deadline Cloud SMF workers and resources in your VPC. The connection is unidirectional, meaning workers can establish a connection to resources in your VPC and transfer data back and forth, but resources in your VPC cannot establish a connection to a worker.

When you connect a VPC resource to a Deadline Cloud service-managed fleet, your workers can access resources in your VPC using a private domain name. Additionally, traffic flows from workers to your VPC resources through VPC Lattice, and resources in your VPC see traffic coming from the VPC Lattice resource gateway.

To learn more, see the VPC Lattice user guide.

Prerequisites

Before connecting VPC resources to your Deadline Cloud service-managed fleet, ensure you have the following:

An AWS account with a VPC containing resources you want to connect.

IAM permissions to create and manage VPC Lattice resources.

A Deadline Cloud farm with at least one service-managed fleet.

VPC resources you want to make accessible (FSx, NFS, license servers, etc.).

Set up a VPC resource endpoint

To set up a VPC resource endpoint, you need to create resources in VPC Lattice and AWS RAM, and then connect those resources to your fleet in Deadline Cloud. To set up a VPC resource endpoint for your SMF, complete the following steps.

To create a resource gateway in VPC Lattice, see Create a resource gateway in the VPC Lattice user guide.

To create a resource configuration in VPC Lattice, see Create a resource configuration in the VPC Lattice user guide.

To share the resource with your Deadline Cloud fleet, create a resource share in AWS RAM. See Creating a resource share for instructions.

While creating a resource share, for Principals, select Service principal from the dropdown, and then enter fleets.deadline.amazonaws.com.

To connect the resource configuration with your Deadline Cloud fleet, complete the following steps.

If you haven't already, open the Deadline Cloud console.

In the navigation pane, choose Farms, and then select your farm.

Choose the Fleets tab, and then select your fleet.

Choose the Configurations tab.

Under VPC resource endpoints, choose Edit.

Select the resource configuration you created, and then choose Save changes.

Accessing your VPC resources

After connecting your VPC resource to your fleet, workers can access it using a private domain name in the following format: <resource_config_id>.resource-endpoints.deadline.<region>.amazonaws.com

This domain is private and only accessible by workers (not from the internet or your workstation).

Authentication and security

For resources requiring authentication, store credentials securely in AWS Secrets Manager, access secrets from your host configuration scripts or job scripts, and implement appropriate file system permissions to control access. Consider security implications when sharing resources across multiple fleets. For example, if two fleets are connected to the same shared storage, jobs that run on one fleet might be able to access assets created from the other fleet.

Technical considerations

When using VPC resource endpoints, consider the following:

Connections can only be initiated from workers to VPC resources, not from VPC resources to workers.

Once established, a connection persists until it is reset, even if the resource configuration is disconnected.

The VPC Lattice connection handles connections between Availability Zones automatically with no additional charges. Your resource gateway must share an Availability Zone with your VPC resource, so we recommend configuring the resource gateway to span all Availability Zones.

Traffic going through the VPC resource endpoint uses Network Address Translation (NAT), which is not compatible with all use cases. For example, Microsoft Active Directory (AD) cannot connect over NAT.