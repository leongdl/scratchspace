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

## 3. OS — NFS Client

NFS v4.1 is available on all Linux distributions by default — no additional packages needed on the worker host (Amazon Linux 2023 includes it). No Dockerfile changes required.

## 4. Mount Command

The job script mounts FSx on the host via the VPC Lattice endpoint, then bind-mounts it into the container:

```bash
# On host (job script)
mkdir -p $HOME/fsx
sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  rcfg-072853a357ca69135.resource-endpoints.deadline.us-west-2.amazonaws.com:/ \
  $HOME/fsx

# In container (via docker run -v)
-v "$HOME/fsx:/mnt/fsx"
```

Inside the container the filesystem is at `/mnt/fsx`.

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
| Port 2049 (NFS) open in SG | ✅ Done |
| Port 443 (HTTPS) open in SG | ✅ Done — required for SSM VPC endpoints |
| FSx in same subnet | ✅ Done |
| VPC endpoint for FSx API | ✅ Done |
| NFS export `insecure` option | ✅ Done — required for Lattice proxy |
| Worker IAM `fsx:DescribeFileSystems` | ✅ Applied to queue role `AWSDeadlineCloudQueueRole-1872629856` and fleet role `AWSDeadlineCloudFleetRole-467892534` |
| Mount in job script | ✅ Done — `$HOME/fsx` on host, bind-mounted to `/mnt/fsx` in container |
| POSIX permissions on `/mnt/fsx` | ⚠️ Set once after first mount if needed |

---

## Why Not Lustre

FSx for Lustre was the original choice (PERSISTENT_2, 1200 GB, 125 MB/s/TiB). It was provisioned and the mount was attempted from Deadline workers via a VPC Lattice TCP resource config endpoint.

It failed with `mount.lustre: Can't parse NID` and later `Invalid argument` because of a fundamental protocol incompatibility: Lustre uses its own network identity system called LNet NIDs. During the mount handshake, the MGS (metadata server) advertises its own NID (e.g. `10.0.0.x@tcp`) back to the client. The client then tries to reconnect directly to that NID — bypassing the Lattice proxy entirely. Since the worker is in Deadline's managed network (`100.100.x.x`) and can't reach `10.0.0.x` directly, the connection fails.

This is not a configuration issue — it's inherent to how Lustre works. Lustre cannot be mounted through any NAT or TCP proxy because the protocol requires direct client-to-server NID connectivity after the initial handshake.

FSx for OpenZFS over NFS v4.1 works correctly through the Lattice proxy because NFS is a standard request/response protocol with no out-of-band reconnection. All traffic flows through the proxy endpoint without the client needing to know the server's real IP.

The Lustre filesystem (`fs-0b20bb08cf7a694ed`) was deleted after confirming the failure. The OpenZFS filesystem (`fs-0fdcec1bc9f64d25d`) replaced it at ~5% of the cost ($6/mo vs ~$174/mo).
