# Why SSM Direct Port Forwarding Doesn't Work for SMF Workers

## The Idea

Instead of the reverse SSH tunnel through an EC2 bastion, use AWS SSM port forwarding directly to the SMF worker:

```
Mac → SSM port forward → Worker:8443 (DCV)
```

This would eliminate the EC2 bastion, VPC Lattice, and the reverse SSH tunnel entirely.

## Why It Doesn't Work

### SSM agent registration requires IAM credentials

The SSM agent needs IAM credentials with `AmazonSSMManagedInstanceCore` permissions to register the instance with AWS Systems Manager. Normally on EC2, the agent gets these automatically from the instance profile via IMDS.

### SMF workers have a dissociated instance profile

On Deadline Cloud Service-Managed Fleet workers, the EC2 instance profile is a minimal Deadline-managed role. The actual fleet role (`AWSDeadlineCloudFleetRole-*`) is not the instance profile — it is fetched and injected by the Deadline worker agent at runtime. The SSM agent, running as a system service, cannot access these credentials via IMDS.

### Can you start the SSM agent with the fleet role credentials explicitly?

Technically yes — the SSM agent respects the standard AWS credential chain, so you could write credentials to `/root/.aws/credentials` or set environment variables before starting it. But this has two blockers:

1. **Credentials are temporary.** The fleet role credentials are STS session tokens that expire. The SSM agent would lose its SSM registration on expiry, requiring a restart with fresh credentials each time.
2. **Requires sudo.** Restarting `amazon-ssm-agent` is a privileged operation. The Deadline job runs as a non-privileged user under the queue role — it cannot restart system services.

## Conclusion

The SSM-direct approach assumes the instance profile is the fleet role, which is not the case in Deadline SMF. The reverse SSH tunnel through an EC2 bastion is the correct architecture because:

- The job runs with queue role credentials (no sudo needed)
- SSH is a userspace operation — no privileged access required
- The worker initiates the connection outbound, which works with SMF's no-inbound-access constraint
- The tunnel persists for the session duration without credential rotation concerns
