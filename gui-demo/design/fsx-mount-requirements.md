# FSx for Lustre — Mount Requirements

Everything needed for Deadline workers to mount `fs-0b20bb08cf7a694ed` at `/mnt/fsx`.

---

## 1. Network

Already configured by `setup_infrastructure.py`. No action needed.

- Security group `sg-0a0d2bdb7a935a990` allows **port 988 (TCP)** inbound from `10.0.0.0/16`
- FSx filesystem is in the same private subnet as the workers
- VPC endpoint `vpce-07af54c91a13de9da` keeps FSx API traffic inside the VPC

## 2. IAM — Worker Role

FSx Lustre mount is network-based, not IAM-gated. However the role running the job script needs `fsx:DescribeFileSystems` if it queries the filesystem at runtime.

The **queue role** is what executes the job script and performs the mount — not the fleet role. Both have been granted the permission for completeness.

| Role | ARN | Policy |
|---|---|---|
| Queue role | `arn:aws:iam::257639634185:role/service-role/AWSDeadlineCloudQueueRole-1872629856` | `FSxDescribeFileSystems` (inline) |
| Fleet role | `arn:aws:iam::257639634185:role/service-role/AWSDeadlineCloudFleetRole-467892534` | `FSxDescribeFileSystems` (inline) |

```json
{
  "Effect": "Allow",
  "Action": "fsx:DescribeFileSystems",
  "Resource": "arn:aws:fsx:us-west-2:257639634185:file-system/fs-0b20bb08cf7a694ed"
}
```

No other IAM changes are needed. FSx for Lustre does not use resource policies or ACLs for mount access.

## 3. OS — Lustre Client

The worker container image must have the Lustre client installed. Add to your Dockerfile:

**Rocky Linux 8 / RHEL 8:**
```dockerfile
RUN amazon-linux-extras install -y epel && \
    curl -o /etc/yum.repos.d/fsx-lustre.repo \
      https://fsx-lustre-client-repo.s3.amazonaws.com/el/8/fsx-lustre-client.repo && \
    dnf install -y kmod-lustre-client lustre-client
```

**Amazon Linux 2:**
```dockerfile
RUN amazon-linux-extras install -y lustre
```

**Amazon Linux 2023:**
```dockerfile
RUN dnf install -y lustre-client
```

## 4. Mount Command

```bash
mkdir -p /mnt/fsx
mount -t lustre \
  fs-0b20bb08cf7a694ed.fsx.us-west-2.amazonaws.com@tcp:/fdyl7b4v \
  /mnt/fsx
```

Must run as **root**. Add to your job entrypoint script before the workload starts.

To verify the mount:
```bash
df -h /mnt/fsx
lfs df /mnt/fsx   # Lustre-specific stats
```

## 5. POSIX Permissions

Once mounted, FSx behaves as a standard Linux filesystem. Default root ownership on a fresh filesystem — set permissions once after first mount:

```bash
# Allow all workers to read/write
chmod 1777 /mnt/fsx

# Or create per-job subdirectories
mkdir -p /mnt/fsx/jobs /mnt/fsx/assets /mnt/fsx/output
chmod 775 /mnt/fsx/jobs /mnt/fsx/assets /mnt/fsx/output
```

Workers running as different UIDs should write to separate subdirectories to avoid conflicts.

## 6. Unmount

```bash
umount /mnt/fsx
```

Always unmount cleanly before terminating the container to avoid stale NFS-style handles on the filesystem.

---

## Summary

| Requirement | Status |
|---|---|
| Port 988 open in SG | ✅ Done by setup script |
| FSx in same subnet | ✅ Done by setup script |
| VPC endpoint for FSx API | ✅ Done by setup script |
| Worker IAM `fsx:DescribeFileSystems` | ⚠️ Apply inline policy `FSxDescribeFileSystems` to queue role `AWSDeadlineCloudQueueRole-1872629856` and fleet role `AWSDeadlineCloudFleetRole-467892534` |
| Lustre client in container image | ⚠️ Must add to Dockerfile |
| Mount command in job entrypoint | ⚠️ Must add to job script |
| POSIX permissions on `/mnt/fsx` | ⚠️ Set once after first mount |
