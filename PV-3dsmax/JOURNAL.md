# PV-3dsmax Iteration Journal

Chronological record of the live implementation/test run. Each entry has enough IDs and
state to resume from that point. Newest entries at the bottom; **Current state** section
is always kept accurate at the top.

---

## Current state (updated 2026-08-04 ~02:15 UTC)

| Resource | Value |
|---|---|
| Account / role | 224071664257 (Admin via `update-ada` alias) |
| Region | us-west-2 |
| Farm | `farm-fd8e9a84d9c04142848c6ea56c9d7568` (ProdUsWest) |
| Fleet | `fleet-25060df816a4493a88dc41840a25fbd6` (PV3dsMaxDebugFleet), min/max=1/1 |
| Queue (exclusive) | `queue-a928e259b15546df833ba209e8a50ca6` (MyQueue) |
| **Cached volume (3ds Max installed)** | `volume-5bef90e3d0ad4ecdb45a868794e49da9`, 500 GiB, **usw2-az3**, state AVAILABLE (detached) |
| Empty volume (unwanted) | `volume-40042c1cbc9f4a068f68919d07e93ebd`, **usw2-az2**, IN_USE by current worker |
| Current worker | `worker-a45b0ad33bbc47d2ba7115195c6b766b` (IDLE, in usw2-az2 — WRONG AZ for cache test) |
| SSM node | none active (mi-0d4a6f0f2f650d6be deregistered with old worker) |
| Host config on fleet | `ssh_to_smf_windows/setup/host_config.ps1` (SSM enabler), timeout 600s |

**Where we are:** M0-M2 complete and validated in-session (simulated warm boot passed).
True warm-boot test is BLOCKED on AZ mismatch: the recycled worker landed in usw2-az2
and got a fresh volume; our cached volume sits in usw2-az3. Volumes are fleet+AZ scoped
and there is no AZ pinning control in the SMF fleet API (`VpcConfiguration` only has
VPC Lattice resource ARNs). Options: (a) cycle the fleet until a worker lands in
usw2-az3, (b) redo the cold install on the az2 volume and accept multi-AZ = one cold
install per AZ, (c) investigate `allowedInstanceTypes` with narrow AZ availability as an
indirect pin (hacky).

**Artifacts on the cached volume (D: when attached), safe but currently inaccessible:**
- `D:\Software\Autodesk\3ds Max 2025\` — full install (~20 GiB)
- `D:\Software\MacrovisionShared\`, `D:\SoftwareData\FLEXnet\` — FlexNet payload copies
- `D:\SoftwareRegistry\snapshots\` — before/after full-hive .reg exports + added-key lists + service/env JSON
- `D:\SoftwareRegistry\graft\` — `autodesk-graft.reg` (4,125 keys, 1.3 MB), per-service .reg + .json
- `D:\installers\3dsMax2025.zip` + extracted tree
- `D:\pv-tools\registry-snapshot.ps1`
- `D:\.install-state.json`

**Local artifacts (this repo):**
- `iteration/00..13-*.ps1` — every script executed on the worker, in order
- `tools/ssm-run.sh` (run ps1 via SSM RunCommand), `tools/poll_cmd.sh`, `tools/wait_worker.sh`, `tools/wait_drain.sh`, `tools/wait_job.sh`
- `host-config/3dsmax-2025-pv-cached.ps1` — production host config draft assembled from the proven steps
- `artifacts/last-graft-validation-output.json` — raw SSM output of the final validation

**To resume:** re-run `update-ada`, then either cycle the fleet (scale 0, wait for drain
via `tools/wait_drain.sh`, scale 1, `tools/wait_worker.sh`) until the worker lands in
usw2-az3 (`aws deadline list-volumes` shows which volume attached), submit
`deadline-cloud-samples/job_bundles/ssh_to_smf_windows` via `bash submit.sh <farm> <queue> 240`,
pull the `mi-*` from the session log, update the node ID default in `tools/ssm-run.sh`,
and run `iteration/13-validate-graft.ps1` style checks. Journal every step here.

---

## 2026-08-03 23:44 — Credentials
`ada credentials update --account 224071664257 --provider=isengard --role=Admin --once`
verified via `sts get-caller-identity`. The user's `update-ada` zsh alias does exactly this.

## 2026-08-03 23:45 — Installer source located
BealineAIMAgents `skills/deadline-workstation/SKILL.md`: DCC installers live in
`s3://common-bealinerezpackage-resources-bucket/3dsmax/{2024,2025,2026}/`
(us-west-2). Default account creds can read the bucket directly (no shared-ro profile
needed). 2025 contents: `3dsMax2025.zip` (5.33 GB), `vray2025.exe` (1.27 GB).
Pattern: `aws s3 presign <uri> --expires-in 7200`, download on worker with `curl.exe`.

## 2026-08-03 23:46 — Persistent volume API confirmed
Installed CLI model was stale. Pulled latest botocore `deadline/2023-10-12/service-2.json`
from GitHub into `~/.aws/models/deadline/2023-10-12/` (botocore loader picks it up).
- `CreateFleet.configuration.serviceManagedEc2.persistentVolumeConfiguration`:
  `mountPath` (required; Windows = drive letter e.g. `D:`), `sizeGiB` (default 250),
  `iops` (3000), `throughputMiB` (125), `lastUsedTtlHours` (168).
- Volume ops: `ListVolumes`, `GetVolume`, `DeleteVolume` (no create — service-managed).
- `VolumeSummary`: `state` (PENDING_CREATION/PENDING_ATTACHMENT/IN_USE/AVAILABLE/PENDING_DELETION),
  `availabilityZoneId`, `attachedWorkerId`.
- Docs (userguide/volumes.html): volumes are per-worker, pooled per fleet+AZ, reused
  across worker lifecycle; `DEADLINE_PERSISTENT_MOUNT` env var set when mounted; if PV
  can't be provisioned the worker fails (no silent fallback). **Answers DESIGN.md open
  questions 1 and 3.**

## 2026-08-03 23:49 — Fleet created
`aws deadline create-fleet` (payload in `/tmp/create_fleet.json`, host config =
`ssh_to_smf_windows/setup/host_config.ps1` inline, timeout 600):
- Fleet `fleet-25060df816a4493a88dc41840a25fbd6` "PV3dsMaxDebugFleet"
- WINDOWS x86_64, 8-32 vCPU, 32-64 GiB RAM, root 250 GiB, **on-demand** (not spot — do
  not interrupt iteration sessions)
- PV: 500 GiB, 3000 IOPS, 250 MiB/s, mountPath `D:`, TTL 168h
- Role: `arn:aws:iam::224071664257:role/BealineE2EFleetRole` (reused from PDXWinFleet)
- min/max 1/1

## 2026-08-03 23:50 — Queue wiring
WindowsQueue was shared with PDXWinFleet → moved to MyQueue
(`queue-a928e259b15546df833ba209e8a50ca6`) as the fleet's exclusive queue:
create-queue-fleet-association (MyQueue), STOP_SCHEDULING_AND_CANCEL_TASKS + delete
association (WindowsQueue). SSM one-time setup already existed in the account
(SSMServiceRole + advanced activation tier).

## 2026-08-03 23:52-00:00 — Worker boot #1
Volume `volume-5bef90e3d0ad4ecdb45a868794e49da9` (500 GiB, usw2-az3) created and IN_USE
before the worker registered. Worker `worker-3ce6672c96a745a0a8f4368705a5c7d4` STARTED
at 00:00. CloudWatch worker log confirmed the SSM host config ran (RDP user, UAC,
DeadlineSsmElevated task).

## 2026-08-04 00:00 — SSM session job #1
`bash submit.sh farm-... queue-a928... 240` → job `job-52fcb743716e4888aaed090f96fe0e49`,
session `session-6e3f4c4538e8419baf62b39a6cc2f664`. Node **mi-0d4a6f0f2f650d6be** Online
at 00:02 (Windows Server 2022 Datacenter). RunCommand (`AWS-RunPowerShellScript`) runs
as SYSTEM — used that for everything instead of interactive sessions.
Helper: `tools/ssm-run.sh <ps1> [timeout] [node] [region]`.

## 2026-08-04 00:04 — Environment verified (iteration/00)
SYSTEM; `DEADLINE_PERSISTENT_MOUNT=D:` at Machine scope; D: = 500 GiB NTFS label
"PersistentVolume", writable; .NET Framework 4.8 present (Release 528449) → **Layer 0
for 2025 is a no-op check**; C: 224 GiB free.

## 2026-08-04 00:05 — Installer download (iteration/01)
Presigned URL → `curl.exe` on worker → `D:\installers\3dsMax2025.zip`.
**5,330,575,388 bytes in 02:29.**

## 2026-08-04 00:06 — Tooling push (iteration/02)
`registry-snapshot.ps1` (12,826 bytes) → `D:\pv-tools\` via base64-in-command.

## 2026-08-04 00:07-00:50 — LESSON: PowerShell registry walk too slow (iteration/03)
`registry-snapshot.ps1 snapshot` (per-key PS walk of HKLM\SOFTWARE) still InProgress
after 25+ min → cancelled. **Use native `reg.exe export` instead.** Confirms DESIGN.md
open question 8 in the worst way.

## 2026-08-04 00:51 — BEFORE snapshot, fast path (iteration/04)
`reg.exe export HKLM\SOFTWARE` (183.4 MB) + `HKLM\SYSTEM\CurrentControlSet\Services`
(3.4 MB) + Win32_Service JSON + machine-env JSON → `D:\SoftwareRegistry\snapshots\
before-20260804-005155-*`. **Total 16 seconds.**

## 2026-08-04 00:52 — Junctions + extract (iteration/05)
Junctions created (link → target):
- `C:\Program Files\Autodesk` → `D:\Software\Autodesk`
- `C:\ProgramData\Autodesk` → `D:\SoftwareData\Autodesk`
- `C:\Program Files\Common Files\Autodesk Shared` → `D:\Software\AutodeskShared`
- `C:\Program Files (x86)\Common Files\Autodesk Shared` → `D:\Software\AutodeskSharedX86`
Zip extracted on D: in 01:14. Setup at `D:\installers\3dsmax2025\3dsMax2025\Setup.exe`.

## 2026-08-04 00:54-01:09 — INSTALL THROUGH JUNCTIONS WORKS (iteration/06)
`Setup.exe -q` → **exit 0 in 14:36**. Payload landed on D: through the junctions
(D: usage 20.4 GiB). `3dsmaxbatch.exe` present. **Answers open question 6: ODIS
tolerates junctioned install paths.** Components installed: 3ds Max 2025, AdODIS,
AdskIdentityManager, Genuine Service.

## 2026-08-04 01:11-01:50 — AFTER snapshot + diff (iteration/07)
After export 18s. Streaming key-set diff (SW before=337,042, after=366,585):
**29,543 added HKLM\SOFTWARE keys**, breakdown:
- 25,415 `SOFTWARE\Microsoft\Windows` (Installer/servicing bookkeeping — EXCLUDE from graft)
- 2,053 `Classes\CLSID` + 617 `Classes\Interface` + ~500 more Classes/* — COM regs (KEEP)
- 203 `SOFTWARE\Autodesk\3dsMax` + 47 `Wow6432Node\Autodesk` + misc Autodesk (KEEP)
- 4-key groups for file associations: 3dsmax/3dschr/3dsifl/3dsms/3dsmxp/3dsmcr, `.max` (KEEP)
New services: **AdskLicensingService** [Auto/Running]
(`C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\...` — inside junction),
**FlexNet Licensing Service 64** [Auto/Running]
(`C:\Program Files\Common Files\Macrovision Shared\...` — **OUTSIDE junction set!**),
**Autodesk Access Service Host** [Auto/Running] (AdODIS, inside junction).
New machine env: `ADSK_3DSMAX_x64_2025 = C:\Program Files\Autodesk\3ds Max 2025\`; Path changed.
Diff artifacts: `added-software-keys.txt`, `added-service-keys.txt` on D:.
PS Group-Object reporting took ~18 min (fine for discovery; not on the boot path).

## 2026-08-04 01:20 — Baseline validation (iteration/08)
`3dsmaxbatch.exe -help` → exit 0 (UTF-16 output). `C:\ProgramData\FLEXnet` +
Macrovision Shared exist on C:. Both licensing services Running.

## 2026-08-04 01:25 — Graft artifacts built (iteration/09)
- `D:\SoftwareRegistry\graft\autodesk-graft.reg`: filtered from AFTER export — keep full
  `SOFTWARE\Autodesk` + `Wow6432Node\Autodesk` subtrees + all *added* keys except
  `SOFTWARE\Microsoft\*` → **4,125 keys, 1.3 MB** (vs 183 MB full hive).
- Per-service `.reg` + `.json` for the 3 services.
- FlexNet payloads copied to volume: `Macrovision Shared` → `D:\Software\MacrovisionShared`,
  `C:\ProgramData\FLEXnet` → `D:\SoftwareData\FLEXnet`.
- `D:\.install-state.json` marker written.

## 2026-08-04 01:35 — Teardown = simulated fresh C: (iteration/10)
Deleted: 3 services (sc delete), `HKLM\SOFTWARE\Autodesk` + Wow6432Node subtrees,
`ADSK_3DSMAX_x64_2025` env var, all 4 junctions (rmdir, targets intact), Macrovision +
FLEXnet dirs on C:. Verified clean; D: payload intact.
*Limitation noted: added Classes/* keys were NOT deleted in the simulation, so their
restore is only proven by `reg import` succeeding, not by absence-then-presence. The
true warm boot covers this.*

## 2026-08-04 01:40 — Graft run (iteration/11 + 12)
- **LESSON:** `reg.exe import` prints "The operation completed successfully." to
  **stderr**; under `$ErrorActionPreference='Stop'` + SSM this became a terminating
  error after the import had already succeeded. Production script must wrap reg.exe
  (`cmd /c` or capture streams). Split into 11 (junctions+files+import) and 12 (resume:
  services+env).
- Junctions re-pointed, FlexNet restored via robocopy, graft.reg imported, services
  re-created with `sc.exe create` from JSON (AdskLicensingService started, FlexNet
  started, **Autodesk Access left disabled by policy**), env contract applied
  (3DSMAX_EXECUTABLE, ADSK_3DSMAX_* set per PR #173, Path prepended).
- Note: registry service keys imported via .reg alone would need a reboot for SCM;
  `sc.exe create` is what makes them live immediately — matches AE script approach.

## 2026-08-04 01:45 — GRAFT VALIDATED (iteration/13)
Fresh SSM process: env contract all correct; `%3DSMAX_EXECUTABLE% -help` → **exit 0,
<1s**; `3dsmax.exe` resolves through junction; **AdskLicensingInstHelper list shows
3DSMAX feature 128Q1 2025.0.0.F registered** — licensing state survived the graft.
Graft wall time ≈ 1-2 min (dominated by robocopy of FlexNet + 1.3 MB reg import).

## 2026-08-04 01:58-02:04 — Fleet cycle for true warm boot
Scaled 0/0; job canceled; worker STOPPING at 02:02; volume detached →
AVAILABLE 02:03; drained 02:04. Deregistered mi-0d4a6f0f2f650d6be. Scaled 1/1.

## 2026-08-04 02:12 — Worker boot #2 + AZ MISMATCH FINDING
New worker `worker-a45b0ad33bbc47d2ba7115195c6b766b` IDLE at 02:12 — but launched in
**usw2-az2**. Deadline created a **new empty volume**
`volume-40042c1cbc9f4a068f68919d07e93ebd` (az2) instead of reusing the cached az3 volume.
**MAJOR DESIGN FINDING:** volumes are fleet+AZ scoped and SMF gives no AZ control
(`VpcConfiguration` = VPC Lattice ARNs only; instanceCapabilities has
allowed/excludedInstanceTypes but no AZ/subnet). Consequences:
- Warm-cache hit rate is per-AZ; a fleet spanning N AZs pays N cold installs and
  the graft must handle "volume attached but empty" (our state-file check does).
- Idle cached volumes in other AZs linger until `lastUsedTtlHours` reaps them (billed).
- This validates the design's cold-path fallback as a first-class path, not an edge case.

## 2026-08-04 02:15 — Checkpoint: work saved to repo
User requested save-first. Copied all executed scripts to `iteration/`, helpers to
`tools/`, scrubbed presigned URL from 01-download.ps1, wrote this journal, assembled
`host-config/3dsmax-2025-pv-cached.ps1` from the proven steps, updated DESIGN.md
open-questions with answers. Journal discipline from here: one entry per step.

## 2026-08-04 02:25 — Decision: validate production script on az2 worker before cycling
Blind-cycling for a usw2-az3 worker is indeterminate (~15 min/attempt). Instead:
1. Run `host-config/3dsmax-2025-pv-cached.ps1` COLD path on the current az2 worker via
   SSM — its attached volume (volume-40042c1cbc9f4a068f68919d07e93ebd) is empty, which
   is exactly the production cold-boot state. This validates the assembled production
   artifact (not just the piecemeal iteration scripts) AND seeds az2 with cache.
2. In-session teardown + re-run script → validates production WARM path.
3. Then update the fleet host config to chain SSM-enabler + production script and cycle
   once: with caches in az2 AND az3, the next worker should warm-graft during real boot
   with no SSM intervention. SSM in afterwards only to verify.
Substitution for SSM testing: SSM RunCommand (SYSTEM) has no fleet-role AWS creds, so
`aws s3 cp` is swapped for a presigned-URL `curl.exe` in the test copy. The fleet-role
`aws s3 cp` path remains in the production script for real host-config context.

## 2026-08-04 02:30 — SSM session #2 + production cold path launched (az2)
- SSM job #2: `job-c3fcec8904514105ab0eb7798455dc1c`, session
  `session-b8f14f10656c4dfd9ab8031a67a1a306`, node **mi-0c47e4d2b5454c5c5** (300 min).
- Test variant of production script saved to `iteration/14-prod-cold-az2.ps1`
  (aws s3 cp → presigned curl for SSM context; URL scrubbed in saved copy).
- Cold-path run on az2 worker: SSM command `d1bdee8f-f9e2-4ecc-a415-a11637b9a12f`.
  Expect ~20 min (download 2:29 + extract 1:14 + install 14:36 + capture + validate).

## 2026-08-04 02:38 — PRODUCTION COLD PATH VALIDATED (az2)
Command `d1bdee8f` Success. Single-file script did: junctions → download (01:32) →
extract (01:02) → `Setup.exe -q` (10:42) → service capture (3) → registry graft export
→ env contract → state file → `3dsmaxbatch -help` OK. **Total 13:19** (faster than the
piecemeal run's ~20; bigger share of I/O stayed on D:). az2 volume
`volume-40042c1cbc9f4a068f68919d07e93ebd` now carries a full cache + graft artifacts.
Next: teardown C: on this worker, re-run the SAME script → must auto-take WARM path.

## 2026-08-04 02:42 — PRODUCTION WARM PATH VALIDATED (az2, in-session)
Teardown (iteration/10) then re-ran the SAME production script: it detected the valid
state file and took the WARM branch automatically. Junctions re-pointed, 9 graft .reg
imported, FlexNet restored, 3 services re-registered (Access disabled), env applied.
**Warm graft total: 00:00:01** (per script's own timer; SSM round trip ~30s).
Full validation (iteration/13): env contract OK, 3dsmaxbatch -help exit 0, 3dsmax.exe
resolves, AdskLicensingInstHelper lists 3DSMAX 128Q1 2025.0.0.F.
Note: az3 volume's graft layout (iteration/09: autodesk-graft.reg + services/*.json +
Macrovision/FLEXnet copies + state file) is layout-compatible with the production
script's Import-InstallerState, so BOTH volumes can serve a production warm boot.

## 2026-08-04 02:45 — Finale plan: true warm boot with production host config
Update fleet host configuration to chain: (1) ssh_to_smf_windows SSM enabler,
(2) production PV script (presigned-URL variant, in case a 3rd-AZ worker goes cold).
Timeout 3600s. Scale 0 → 1. New worker executes the real host-config path at boot with
no SSM babysitting. Then submit SSM job only to VERIFY the result. Success criteria:
worker CloudWatch log shows "WARM boot" + "Total (warm graft)" < 1 min (if az2/az3),
or a complete cold install (if new AZ), and validation passes on the box.

## 2026-08-04 02:45 — FINDING: hostConfiguration.scriptBody max = 15,000 chars
UpdateFleet rejected the combined SSM-enabler + PV script (33,128 chars, base64-embedded
parts): `maximum allowed: 15000`. Also: BealineE2EFleetRole has NO s3 permissions
(deadline worker actions + logs + kms only), so in-script `aws s3 cp` would fail in
real host-config context too — the presigned-URL variant is required for this fleet
unless the role gains s3:GetObject (production docs should keep documenting the
fleet-role-S3 pattern; presigned URLs from ada session creds die with the session).
Consequences for the design: single-file host config must stay under 15k chars —
the PV production script alone is 13.6k (fits); chaining the SSM debug enabler does
not. For the true warm-boot test: host config = PV script ONLY, verification via the
worker's CloudWatch host-config log (no SSM needed on the box to prove WARM path).

## 2026-08-04 02:47 — True warm boot: fleet host config = PV script only
Setting fleet host configuration to the presigned-URL production variant (13,601 chars),
timeout 3600s. Then scale 0 → 1. Expected: new worker in az2/az3 finds cached volume,
host-config log shows "=== WARM boot ===" + "3dsmaxbatch responds OK" with sub-minute
graft; if a new AZ, shows full COLD path (presigned URL valid until ~04:25 UTC).

## 2026-08-04 02:53 — ✅ TRUE WARM BOOT VALIDATED — END-TO-END PROOF
Fleet host config = production PV script (13,601 chars, presigned variant), timeout
3600s. Cycled 0 → 1. New worker `worker-5be24165644a41db87faf97586543643` launched in
**usw2-az2** and **reattached the cached volume** `volume-40042c1cbc9f4a068f68919d07e93ebd`.
Host-config CloudWatch log (stream worker-5be2...):
```
=== WARM boot: grafting cached install ===
Junction: x4 ... Imported: x9 .reg ... Registered service: x3
3dsmaxbatch responds OK
Total (warm graft): 00:00:04
Finished running Host Configuration Script, exit code: 0
```
**Worker-ready with 3ds Max in 4 seconds of host-config time, vs 13-20 min cold.**
This validates the full design on a real boot path: volume reuse, state-file detection,
junction re-point, registry graft, service re-registration, env contract, self-test.

## Final state / cost note
- Fleet PV3dsMaxDebugFleet at min/max 1/1 (on-demand Windows, 8-32 vCPU) with worker
  `worker-5be24165644a41db87faf97586543643` idle + TWO 500 GiB gp3 volumes (az2
  production-layout cache IN_USE, az3 iteration-layout cache AVAILABLE, TTL 168h).
  Scale to 0/0 when not iterating: `bash /tmp/scale_when_ready.sh 0 0`
  (or delete az3 volume: `aws deadline delete-volume --volume-id volume-5bef90e3d0ad...`).
- Fleet host config currently contains a presigned URL that expires ~04:25 UTC — only
  matters if a worker lands in a brand-new AZ (cold path). Replace with fleet-role
  `aws s3 cp` + s3:GetObject grant for anything long-lived.

## Remaining gaps (next iteration targets)
1. Real scene render (not just -help) — needs a licensed render + job submission
   through Deadline (deadline-cloud-for-3ds-max adaptor not yet installed — add
   `pip install deadline-cloud-for-3ds-max` via Max's Python to cold path + graft-check).
2. `job-user` validation (design open q9): all tests ran as SYSTEM/host-config context;
   submit an actual Deadline job to exercise job-user through the junctions.
3. Renderer plugin (V-Ray/Corona) layer on the cold path.
4. AZ cache fragmentation (open q11): decide accept-and-document vs mitigation.
5. Classes/CLSID coverage (open q12): production graft imports Autodesk + file-assoc
   classes only; full COM set may be needed for real renders — the az3 volume's
   iteration graft (full added-key set) is the comparison point.

## 2026-08-04 03:00 — Documentation saved
- `REGISTRY-KEYS.md`: full discovered-key breakdown, service table, graft variants,
  where the on-volume artifacts live.
- `S3-INSTALLERS.md`: shared bucket contents + presign/fleet-role access patterns.
- Remaining helpers copied to `tools/` (scale_when_ready, get_node, poll_cmd2).

## 2026-08-04 03:01 — Next: minimal_test bundle from deadline-cloud-for-3ds-max
Clone github.com/leongdl/deadline-cloud-for-3ds-max (mainline), read
test/integ/test_scripts/minimal_test + integ test code, submit with
`deadline bundle submit` against farm ProdUsWest / MyQueue / PV3dsMaxDebugFleet.
This exercises journal gaps #1 (adaptor) and #2 (job-user through junctions):
expect to need `deadline-cloud-for-3ds-max` adaptor available to the job. Current
worker (worker-5be24165644a41db87faf97586543643, warm-grafted) has NO adaptor and NO
SSM enabler (host config is PV-script-only now).

## 2026-08-04 03:05-03:28 — Adaptor install added; queue JA wired; strict-mode bite #2
- MyQueue given jobAttachmentSettings `{leongdldevbucket, DeadlineCloud}` (queue role
  already had matching S3 policy). Cloned github.com/leongdl/deadline-cloud-for-3ds-max;
  minimal_test = 4 tasks (frames 1-2 × TopCam/SideCam), Scanline, 1280x720 jpg via
  `3dsmax-openjd daemon`; integ test compares to expected_images with tolerance 2.
- Host config updated: `Install-Adaptor` (pip install deadline-cloud-for-3ds-max into
  Max's junctioned Python) on all paths. Deployed variant 14,393 chars (fits 15k).
- Fleet cycled. Worker `worker-92e2e1da123147179ececd2eae32a78d` attached the **az3**
  volume (iteration-layout cache) — WARM graft succeeded (autodesk-graft.reg imported,
  services registered) **but Install-Adaptor threw on pip's stderr WARNING** ("scripts
  not on PATH") — same strict-mode class as reg.exe (open q13). Fallback correctly
  invalidated + went COLD, but cold path would re-throw at the same spot.
- Fix: pip/ensurepip routed via `cmd /c ... >nul 2>&1` in Install-Adaptor. Will push
  fixed host config and re-cycle. LESSON (generalized): in host-config strict mode,
  EVERY native tool that writes benign output to stderr must be stream-contained
  (reg.exe, pip, ensurepip; robocopy handled via exit-code policy).

## 2026-08-04 03:30-04:10 — Shell wedge + fix deployment
Dev-box foreground shell wedged ~30 min (commands timing out with no output); switched
to background process channel. Confirmed the fixed payload (14,561 chars, pip routed
via cmd) was written before the wedge, pushed via update-fleet (HC-UPDATED). Meanwhile
worker `worker-95712b4a63d14d94a48b2861681e122c` had booted with the BUGGY script on
the az3 volume: its cold install will complete (~14 min) then throw at Install-Adaptor
BEFORE the state file is written → host config fails → worker likely terminated by
service. az3 volume state after that failed run: fresh install present but NO
.install-state.json (iteration/09's state file was Remove-Item'd by the fallback) —
next attach goes COLD again (correct, if wasteful). Cycling fleet now so the next
worker runs the FIXED script.

## 2026-08-04 04:15 — Registry graft documented in host-config/
- `host-config/registry-subtrees.json`: machine-readable manifest — production vs
  iteration graft subtree lists, exclusion list with reasons, Autodesk subtree child
  counts, service table with warm-boot policies, env var contract, artifact locations.
- `host-config/README.md`: format + mechanism explainer. Key points: graft = native
  .reg files (reg.exe export/import), JSON only for service defs (sc.exe create needs
  it for immediate SCM registration; .reg import of Services keys needs a reboot) and
  the state file; values live on the volume (capture-don't-enumerate), subtree list
  lives in the repo; stderr-containment rule for reg.exe/pip under strict mode.
Fleet cycle for the fixed adaptor script still in progress in background terminal.

## 2026-08-04 04:25 — Artifact provenance answered + hand-off prompt written
User asked where the .reg files lived: **on the EBS persistent volumes only** — the
cold path writes `reg.exe export` output to `D:\SoftwareRegistry\graft\` on the
worker; the volume detaches into the fleet's per-AZ pool with the files inside.
Never in S3, never on this dev box; the repo only had transcriptions of SSM output.
Saved so nothing needs reverse engineering:
- `artifacts/create-fleet-payload.json` — exact create-fleet payload (HC body elided)
- `artifacts/deployed-host-config-2025-with-adaptor.ps1` — what's on the fleet now
  (presigned URL scrubbed)
- `artifacts/warm-graft-pip-stderr-failure.log.json` — CloudWatch evidence of the pip
  strict-mode failure
- `artifacts/README.md` — provenance table incl. what remains volume-only and how to
  pull it (added-software-keys.txt + production .reg files → artifacts/from-volume/)
- `PROMPT-3dsmax-2026-2027.md` — complete agent prompt to reproduce the methodology
  for 3ds Max 2026/2027: reading order, AWS context, 12-step method, traps T1-T10,
  success criteria, inherited open items (2027 installer must be built — no S3 prefix).
Fleet cycle still draining worker-95712b4a (buggy-script cold install holds off the
scale-down; will fail at Install-Adaptor then terminate).

## 2026-08-04 04:35-04:45 — S3 SNAPSHOT TIER added (user request) + bootstrap deployment
New optimization on top of the PV cache: first cold worker zips the volume payload
(Software + SoftwareData + SoftwareRegistry graft + .install-state.json — i.e. the
junction-target files AND the registry capture) and publishes it to S3; any later
worker with an empty volume (other AZ, TTL-reaped, new fleet) restores from the zip in
minutes instead of reinstalling. 1-byte-ish `installing.token` claimed atomically via
S3 conditional write (`put-object --if-none-match '*'`, racy check-then-put fallback
for old CLIs) prevents duplicate installs; token older than 75 min with no zip =
crashed installer, taken over. Boot ladder now:
  PV-WARM (4s) -> S3-WARM (zip dl+extract, est 3-6 min) -> WAIT (poll zip) -> COLD (once EVER per version)
PV-WARM boots also opportunistically SEED the zip if S3 lacks it (token-guarded), so
the tier populates without any new cold install. This largely neutralizes trap T5
(per-AZ volume pools) and turns open question 11 into a solved cost note.
Implementation:
- `host-config/3dsmax-2025-pv-s3-cached.ps1` (18 KB, fully commented) — new master.
- `host-config/bootstrap-host-config.ps1` (900 chars) — fleet scriptBody now just
  downloads the master from S3 and runs it; kills trap T2 (15k limit) permanently.
  Master uploaded to s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2025/host-config.ps1.
  BOOTSTRAP-DEPLOYED on the fleet.
- IAM: inline policy `PvCacheS3Access` added to BealineE2EFleetRole (GetObject/
  PutObject/DeleteObject on leongdldevbucket/DeadlineCloud/pv-cache/* + scoped
  ListBucket). NOTE: role is shared by other fleets in this account — scoped, additive,
  reversible (`aws iam delete-role-policy --role-name BealineE2EFleetRole --policy-name PvCacheS3Access`).
- Installer staged into our own bucket so the fleet role can read it without presigned
  URLs: first server-side copy failed (`GetObjectTagging` AccessDenied cross-account);
  retried with `--copy-props none` — in progress.
- State-file check relaxed to compare installer basename (not full URI) so re-staging
  the same zip in a different bucket doesn't invalidate good volumes.
- tar.exe (bsdtar, ships on WS2019+) for zip create/extract — NOT Compress-Archive
  (too slow at 20 GB); all native calls stderr-contained per T1.
Buggy worker-95712b4a still burning down (slow reinstall over existing files, 24 min
elapsed); on its Install-Adaptor failure the service replaces it → replacement runs the
BOOTSTRAP config. Expected replacement behavior: lands az2 (state file valid) → PV-WARM
+ seeds S3 zip; or az3 (no state file) → S3-WARM if zip exists by then, else COLD.

## 2026-08-04 05:07 — ✅ RENDER TEST PASSED — PIXEL-PERFECT
Plot twist resolved: worker-95712b4a was never running the buggy script — its host
config started ~04:11, AFTER the pip fix deployed at 04:07. It ran the fixed monolithic
script COLD on the az3 volume (state file had been deleted by the earlier crashed run):
Download 00:00 (cached zip on volume), Extract 00:00 (cached), Install 25:12 (reinstall
over existing files is slower than clean 14:36), services captured, graft exported,
**adaptor installed**, exit 0, worker IDLE.
Render: submitted `render-test/minimal_test_bundle` (scene uploaded via job
attachments to leongdldevbucket) → job-82b4f07b310f4144b7a5459be347a68f →
**4/4 tasks SUCCEEDED** (frames 1-2 × TopCam/SideCam, Scanline, 1280x720) in ~3 min.
Downloaded outputs and compared against the repo's expected_images with the integ
test's method (numpy allclose, tolerance 2):
```
MATCH State01_test_001_SideCam.jpg max_diff=0.00
MATCH State01_test_001_TopCam.jpg  max_diff=0.00
MATCH State01_test_002_SideCam.jpg max_diff=0.00
MATCH State01_test_002_TopCam.jpg  max_diff=0.00
```
RESOLVED: open q9 (job-user renders through junctions), open q5 partially (UBL
licensing works for real renders on SMF). Note: this render ran on a COLD-installed
worker; the render-on-grafted-registry case (q12) is validated next via a bootstrap
cycle → PV-WARM graft → re-render.
Submission gotchas: `--yes` cancels on "unknown locations" (asset paths outside known
roots) — pipe `y` confirmations instead; `deadline job download-output` fetched the 4
outputs to render-test/output/.

## 2026-08-04 05:08 — Finale: bootstrap + S3-tier demonstration cycle
Fleet HC = bootstrap (deployed 04:38, current worker predates it). Cycling: expect
replacement worker to (1) bootstrap-fetch the master from S3, (2) PV-WARM graft (both
volumes now hold valid state files), (3) opportunistically SEED the S3 zip, then (4)
re-render minimal_test on the grafted worker to close q12.

## 2026-08-04 05:20-06:10 — Bootstrap + token verified live; tar publish bug found + fixed
Worker `worker-33ce190f54c54626b072f24692669b38` (replacement after render cycle)
landed in **usw2-az1** — a THIRD AZ, brand-new empty volume
`volume-0a34db36a9d14445b6c8c177894ff3b7`. Perfect live demo of why the S3 tier
matters. Verified from its CloudWatch log:
- `Bootstrap: fetched s3://...host-config.ps1` — bootstrap pattern works.
- `install token claimed (conditional)` — **S3 conditional write (--if-none-match)
  works on the AMI's CLI**; atomic claim confirmed.
- COLD path: Download 01:29 (from own bucket via fleet role — PvCacheS3Access works),
  Extract 01:03, Install 11:33, capture + adaptor OK, **Total 15:37**, exit 0.
- BUT: `WARNING: S3 publish failed (non-fatal): tar create failed: 1` — non-fatal
  design held (worker came up healthy), zip not published.
Root cause of tar failure (two suspects, both addressed):
1. `-C "D:\"` — trailing backslash before the closing quote is eaten by Windows argv
   parsing; bsdtar got a mangled path. Fix: forward-slash form `-C "D:/"`.
2. Running licensing services can hold locks inside the payload. Fix: stop the three
   services around the archive, restart in `finally`.
Also: new `Invoke-Tar` captures tar's stderr to a temp file and includes it in the
throw (the old stream-discard hid the actual error — diagnosability lesson on top of
the T1 containment rule).
Updated master uploaded to S3 (19,921 bytes, 06:03:55Z). Volumes now: az1 (fresh
install + state, IN_USE), az2 (production cache, AVAILABLE), az3 (cache, AVAILABLE) —
ALL THREE hold valid caches; any AZ landing = PV-WARM. Next cycle verifies the fixed
zip publish (seed on PV-WARM) and re-renders on a GRAFTED worker (closes q12).

## 2026-08-04 17:48 — ✅ 2025 COMPLETE: graft render pixel-perfect + S3 zip published
Worker `worker-726478447f8b4d1a8e19ec092b477b40` (bootstrap + fixed tar script):
- **PV-WARM graft: 00:00:15** (incl. adaptor upgrade check) — exit 0.
- **S3 zip seeded**: token claimed (conditional), `Zip create (5.5 GB): 00:21:28`,
  `Zip upload: 00:00:34` → s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2025/pv-payload.zip.
  (Zip create is long because tar+deflate of ~20 GB is single-threaded — acceptable
  one-time cost; candidate optimization: zstd or store-only zip.)
- Render job-e9cd8292d8724923a74e267e3a111bdd on the GRAFTED worker: **4/4 SUCCEEDED,
  all four images max_diff=0.00** vs expected. **CLOSES open question 12** — the
  production graft's minimal registry set (Autodesk subtrees + file-assoc classes,
  no bulk COM keys) is sufficient for real Scanline renders via the adaptor.
2025 scorecard: COLD 13-26 min (once), PV-WARM 4-15 s, render validated on both cold
and grafted workers, S3 zip published. Remaining 2025 item: demonstrate S3-WARM
restore (delete volumes → fresh volume → restore from zip) — next.

## 2026-08-04 17:50 — 2026 parallel version started (S3-first architecture)
Per user direction: S3 tier is PRIMARY, PV is the add-on. New
`host-config/3dsmax-2026-s3-cached.ps1` (gen-2 architecture): cache root =
DEADLINE_PERSISTENT_MOUNT if present else C:\DeadlineCache on local disk — the
junction layout makes the zip identical either way, so S3 restore works on fleets
WITHOUT persistent volumes too (fresh workers pay zip-restore minutes instead of
install; PV upgrades that to seconds). Ladder: PV-WARM (if PV) → S3-WARM → WAIT →
S3-COLD (once per version farm-wide, token-guarded). 2026 installer staged copy
in progress; plan: separate fleet PV3dsMax2026Fleet (clean volume pool, avoids
mixing 2025/2026 payloads under the same junction targets on shared volumes).

## 2026-08-04 18:20 — ✅ 2025 S3-WARM DEMO COMPLETE — all three tiers proven with renders
Deleted az1/az2 volumes (kept az3 — it holds the discovery snapshots), cycled the 2025
fleet. New worker `worker-71af08f91cb3446294149c8d2dae8ebd` got a BRAND-NEW az1 volume
(`volume-b410b188...`; service created fresh rather than reusing az3 — volume selection
is not cache-aware, more evidence the S3 tier is the right global layer):
```
=== S3-WARM boot: restoring volume from S3 zip ===
Zip download: 00:01:42 | Zip extract: 00:01:33 | graft + adaptor + self-test
Total (S3-warm restore + graft): 00:03:34 — exit 0
```
Render job-83c50a2c60de445f9ab759c3330c3666 on the S3-restored worker:
**4/4 SUCCEEDED, all images MATCH (tolerance 2).**
FINAL 2025 SCORECARD (all render-validated):
| Path | Time | Validated by |
|---|---|---|
| PV-WARM | 0:15 | render pixel-perfect (job-e9cd...) |
| S3-WARM | 3:34 | render pixel-perfect (job-83c5...) |
| COLD (once/version) | 13-26 min | render pixel-perfect (job-82b4...) |

## 2026-08-04 18:22 — 2026 S3-COLD underway on new fleet
Fleet `fleet-6a12c81636e442439541dc5c3c7a19dd` (PV3dsMax2026Fleet, bootstrap-2026 HC),
worker `worker-6819ba9899444f86b850190e411269ae`, fresh az3 volume. Log so far:
bootstrap fetched 2026 script, token claimed (conditional), S3-COLD: Download 01:49,
Extract 01:13, **Install 12:39**, 3 services captured, **adaptor installed, 3dsmaxbatch
responds OK** — 3ds Max 2026 needs no Layer-0 additions on the WS2022 AMI and the
version-agnostic capture (subtree exports + same 3 services) holds. Zip publish phase
running (~20 min). Next: scale 2025 fleet 0/0, render on 2026, then delete-volume cycle
to demo 2026 S3-WARM restore.

## 2026-08-04 19:45-19:55 — 2026 DELTA FOUND: .NET Core runtime lives outside the junctions
2026 S3-WARM restore itself worked (`Total (S3-warm restore + graft): 00:05:10`,
worker-590510b88da745dfbca5d8039d06daf7, fresh volume) BUT the render failed 4/4:
session log shows 3dsmaxbatch exit -11, Max.log: **"Terminating due to required .NET
Core version not present"**. Diagnosis: 3ds Max 2026 requires the .NET Desktop
Runtime, which ODIS installs to `C:\Program Files\dotnet` — OUTSIDE the junction set —
so cold workers have it (renders passed) but restored workers don't. Exactly the
predicted per-version Layer-0 delta; also exposed that `-help` does not exercise full
Max init (self-test gap).
Fixes to `3dsmax-2026-s3-cached.ps1`:
1. Export-InstallerState: robocopy `C:\Program Files\dotnet` → `$SW\dotnet` + export
   `HKLM\SOFTWARE\dotnet` (+Wow6432Node) into the graft (same pattern as FlexNet).
2. Import-InstallerState: restore dotnet payload before registry import.
3. Test-Render hardened: also require `dotnet --list-runtimes` to list
   `Microsoft.WindowsDesktop.App` — catches this class at boot instead of at render.
2025 unaffected (renders pixel-perfect on all paths; 2025 uses .NET Framework 4.8
which ships on the AMI). Redeploying: upload fixed script, cancel failing job, delete
the stale 2026 zip (lacks dotnet), cycle → deterministic COLD → publishes good zip →
render; then delete-volume cycle → S3-WARM with good zip → render.

## 2026-08-04 21:45 — ✅✅ PROJECT COMPLETE: 2025 + 2026 both fully validated
Post-fix 2026 sequence (all on fleet PV3dsMax2026Fleet):
1. Fixed script deployed; stale zip + token deleted; fleet cycled.
2. Worker `worker-627618cffe0f42479a17ba147f59f0a7`: S3-COLD with the .NET fix —
   Install 18:04, `Captured .NET Core runtime payload + registry`, hardened self-test
   passed (`3dsmaxbatch responds OK; .NET Desktop Runtime present`), corrected zip
   published (6.54 GB, 20:48 UTC). Render job-927381f86fde4f6d803afe4203d3cd3f:
   **4/4 SUCCEEDED, ALL MATCH.**
3. CAPSTONE: volume deleted, fleet cycled. Worker `worker-ff28172c7aac4f13a808bd2fd37ab900`
   on a fresh volume: **S3-WARM restore 04:46** (download 2:24, extract 2:00,
   `Restored .NET Core runtime`, dotnet reg imported, self-test passed, exit 0).
   Render job-efb65054c70148c895a37ce67216fcbd: **4/4 SUCCEEDED, ALL MATCH.**

FINAL SCORECARD (every cell render-validated pixel-perfect vs expected_images):
| Version | COLD (once/version, farm-wide) | S3-WARM (any AZ, fresh volume) | PV-WARM |
|---|---|---|---|
| 3ds Max 2025 | 13-26 min | 3:34 | 0:15 |
| 3ds Max 2026 | ~39 min incl. zip publish | 4:46 | (same mechanism; not separately re-timed) |

End state:
- Both fleets scaled 0/0. S3 cache: 3dsmax-2025/pv-payload.zip (5.96 GB) +
  3dsmax-2026/pv-payload.zip (6.54 GB) + host-config.ps1 each + installers/.
- Volumes: deleted for 2026; 2025 keeps az3 discovery volume + az1 (TTL 168h reaps
  or delete-volume manually).
- IAM: PvCacheS3Access inline policy remains on BealineE2EFleetRole (scoped,
  documented in artifacts/README.md).
- Repo: host-config/ has gen-1 (PV inline), gen-1.5 (2025 PV+S3), gen-2 (2026
  S3-first) + bootstraps; all findings in DESIGN/REGISTRY-KEYS/registry-subtrees.json;
  2027 handoff prompt updated (PROMPT-3dsmax-2026-2027.md).
Key 2026-specific lesson for the record: 3ds Max 2026 requires the .NET Desktop
Runtime (ODIS installs to C:\Program Files\dotnet, outside junctions) — capture/restore
it like FlexNet, and self-test with `dotnet --list-runtimes` because `-help` does not
exercise full Max init.
