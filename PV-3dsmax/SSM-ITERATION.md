# Iterating on the PV install via SSM before committing to a host config

The host configuration loop (edit script → update fleet → cycle workers → wait for boot →
read CloudWatch) costs 10-20 minutes per attempt and gives you log lines, not a shell.
For a discovery-heavy problem like "which registry keys does the 3ds Max installer
create," that loop is far too slow.

The repo already ships the vehicle:
[`job_bundles/ssh_to_smf_windows`](../deadline-cloud-samples/job_bundles/ssh_to_smf_windows/README.md)
registers a Windows SMF worker as an **SSM hybrid managed node** for the duration of a
job, giving an interactive PowerShell or RDP session on the exact worker environment —
same AMI, same `job-user`, same persistent volume mount — that the eventual host config
will run in.

## How the bundle works (summary)

1. A fleet host config (`setup/host_config.ps1`) pre-installs a SYSTEM-elevated scheduled
   task (`DeadlineSsmElevated`), makes `job-user` a local admin, creates an RDP admin
   user, and enables RDP. This is needed because `amazon-ssm-agent.exe -register`
   requires an unfiltered admin token, and processes spawned by the Deadline worker run
   with a UAC-filtered token.
2. `submit.sh` / `submit.ps1` creates a one-time SSM hybrid activation
   (`aws ssm create-activation`) and submits the job.
3. The job re-registers the pre-installed SSM agent as a hybrid `mi-*` node and prints the
   node ID to the job log, then keeps the session alive for `SessionMinutes`.
4. You connect: `aws ssm start-session --target mi-XXXXXXXXX` (PowerShell as `ssm-user`),
   or RDP over an SSM port-forward as the `RDP` admin.
5. On session expiry the job deregisters the node.

One-time account setup: `SSMServiceRole` with `AmazonSSMManagedInstanceCore`,
advanced-instances tier enabled, outbound HTTPS from the worker VPC to
`ssm.` / `ssmmessages.` / `ec2messages.<region>.amazonaws.com`.

## Fleet setup for iteration

Create a dedicated **debug fleet** (never mix with production):

- Windows SMF, instance type comparable to the production render fleet
- **Persistent volume attached** (100-200 GiB) — the whole point is to iterate against
  the real `DEADLINE_PERSISTENT_MOUNT`
- Host configuration: paste `ssh_to_smf_windows/setup/host_config.ps1` (timeout ≥ 300s)
- Fleet role: the SSM bundle's requirements **plus** `s3:GetObject` on the installer
  objects (the production fleet needs this anyway, so testing it here is a feature)
- min/max workers 1/1 while iterating; 0/0 when done

Note the layering: during iteration, the fleet's host config is the **SSM enabler**, not
the 3ds Max installer. The 3ds Max install steps are run manually (or as pasted script
blocks) inside the SSM session. Only in M5 do the proven steps move into the production
host config and the SSM host config comes off the fleet.

## The iteration loop

```
submit ssh_to_smf_windows job (SessionMinutes=240 or so)
  └─ get mi-* from job log
       └─ aws ssm start-session --target mi-*   (or RDP port-forward)
            │
            ├─ 0. Verify environment:
            │      [Environment]::GetEnvironmentVariable('DEADLINE_PERSISTENT_MOUNT','Machine')
            │      Get-Volume; test volume write access        → answers open questions 1/3
            │
            ├─ 1. BEFORE snapshot:
            │      .\registry-snapshot.ps1 snapshot -Label before
            │
            ├─ 2. Create junctions, run the install steps manually
            │      (aws s3 cp, Expand-Archive, Setup.exe -q, renderer installer)
            │      — time each phase
            │
            ├─ 3. AFTER snapshot + diff:
            │      .\registry-snapshot.ps1 snapshot -Label after
            │      .\registry-snapshot.ps1 diff -Before <before> -After <after>
            │      → THE deliverable of M0: the authoritative key/service list
            │
            ├─ 4. Export vendor subtrees:
            │      .\registry-snapshot.ps1 export -OutDir $env:DEADLINE_PERSISTENT_MOUNT\SoftwareRegistry
            │
            ├─ 5. Simulate a warm boot IN-SESSION (fast approximation):
            │      delete the vendor registry subtrees, delete the services,
            │      clear the machine env vars, re-point junctions,
            │      .\registry-snapshot.ps1 apply -RegDir ...\SoftwareRegistry
            │      re-create services from JSON, re-set env vars
            │      → test: 3dsmaxbatch.exe -help, then a licensed render
            │
            └─ 6. TRUE warm boot: scale fleet to 0, back to 1 (volume reattaches),
                   submit a fresh SSM job, verify the volume state survived,
                   run only the graft steps, test again
```

Keep a running `install-log.md` of timings and failures per session; copy it off the box
(or to the volume) before the session expires.

### Working as the right user

SSM sessions run as `ssm-user`; RDP runs as the `RDP` admin. Render jobs run as
`job-user`. After the graft works as admin, re-test as `job-user`:

- RDP in as `RDP`, set a password on `job-user`
  (`Set-LocalUser -Name job-user -Password ...`), reconnect as `job-user`, and run
  `3dsmaxbatch.exe` — this catches per-user vs machine registry/env assumptions and
  junction ACL problems (open question 9).

## Test gaps: what SSM iteration proves vs what only a real host config run proves

SSM iteration compresses the discovery loop from ~15 minutes to seconds, but the two
execution contexts are not identical. Track these gaps explicitly and close each one in
M5 with a real host-config validation pass on a fresh fleet.

| # | Gap | Why it differs | How to close |
|---|---|---|---|
| G1 | **Execution identity.** Host config runs as Administrator via the Deadline agent; SSM session runs as `ssm-user`/`RDP` interactively. | Different token, profile, and `%TEMP%`; interactive sessions have a loaded user profile, host config may not. Installers occasionally write to the running user's hive (HKCU) — invisible if we only diff HKLM. | Snapshot tool also diffs HKCU during discovery; anything found in HKCU must be moved to HKLM or set per-boot. M5 fresh-fleet run is the final arbiter. |
| G2 | **Boot-time ordering.** Host config runs *before* the worker takes jobs, on a cold OS. In-session iteration runs on a machine that already booted and ran the SSM host config. | Services already warm, network already up, Deadline agent already initialized. A dependency that "just works" mid-session may not exist at host-config time. | M2's "true warm boot" step and the M5 fresh-fleet pass. |
| G3 | **The SSM host config itself perturbs the box.** It adds `job-user` to Administrators, disables the UAC consent prompt, enables RDP. | The production fleet won't have these. An install step that silently depended on `job-user` being admin would pass in iteration and fail in production. | Production host config runs with none of the SSM modifications; M5 validates on a fleet with *only* the production script. Re-test `job-user` render with default (non-admin) group membership. |
| G4 | **Timeout envelope.** Host config has a hard `scriptTimeoutSeconds` (max 3600); an SSM session lets a slow step run indefinitely. | A cold install that takes 55 min in-session will kill the fleet's host config. | Record per-phase timings every session; keep the cold-path budget under ~45 min with margin. If it can't fit, the pattern still works — cold installs just need warm-pool management. |
| G5 | **Non-interactive failure modes.** `Setup.exe -q` can still pop a hidden dialog or wait on input; interactively you'd notice and can kill it, host config just hangs to timeout. | No console, no desktop in host-config context. | During iteration, run installers via `Start-Process -Wait -PassThru` and check exit codes rather than watching windows; grep installer logs (`%TEMP%\Autodesk`, ODIS logs) for prompts. |
| G6 | **Reboot-pending state.** In-session we can reboot and reconnect; host config cannot reboot. | If the installer sets `PendingFileRenameOperations`, in-session testing after a manual reboot would hide the constraint. | Never reboot between install and render-test during iteration; explicitly check `PendingFileRenameOperations` after install (open question 7). |
| G7 | **Volume attach timing.** In-session the volume is long-attached; on a real boot, host config may race volume mount. | If `DEADLINE_PERSISTENT_MOUNT` is set but the mount isn't ready, the graft fails spuriously. | Production script starts with a bounded wait-for-mount loop; M5 fresh-boot validation exercises it for real. |
| G8 | **Session-scoped env pollution.** Vars exported in the SSM shell leak into the same-session render test, masking a missing Machine-scope var. | Machine env changes require a new process to be visible; interactive shells accumulate state. | Test renders from a *new* PowerShell process spawned after env application (`Start-Process powershell -ArgumentList ...`), never from the shell that set the vars. The in-session warm-boot simulation (step 5) explicitly clears vars first. |
| G9 | **First-run-per-user behavior.** 3ds Max may do per-user first-run setup (workspace, ENU folder) under whichever user first launches it. In iteration that's `ssm-user`/`RDP`; in production it's `job-user`. | Per-user state lives in that user's profile and HKCU. | Always do final render validation as `job-user` (see "Working as the right user"), and treat any per-user requirement found as something the host config must pre-seed for `job-user`. |
| G10 | **CloudWatch observability.** In-session you read output directly; the production script's only output channel is the worker log stream. | Debugging style that relies on interactive inspection won't transfer. | Production script keeps the AE script's discipline: strict mode, single trap writing `ERROR:` + stack to stdout, per-phase `Write-Duration` lines. |

The rule of thumb falling out of this table: **SSM iteration is for discovery and
correctness of the install/graft logic; it is necessary but not sufficient. Every
milestone gets its final sign-off from a fresh worker boot running only the production
host config** (M5), with G1-G10 used as the review checklist for what might differ.

## Deregistration hygiene

- Sessions self-deregister on expiry, but if you kill a job early, deregister manually:
  `aws ssm deregister-managed-instance --instance-id mi-XXXXXXXXX`
- The submitters create activations with `--registration-limit 10` because Deadline
  retries consume slots — fine for iteration.
- Scale the debug fleet to 0 when not iterating. The RDP user and relaxed UAC are
  explicitly not for production (per the bundle's own security note).
