# Agent prompt: build PV-cached host configs for 3ds Max 2026 and 2027

Copy everything below the line into a fresh agent session running in the
`/home/leongdl/moonray` workspace.

---

## Mission

Produce validated persistent-volume-cached Deadline Cloud host configuration scripts
for **3ds Max 2026** and **3ds Max 2027**, following the methodology already proven
for 3ds Max 2025 in `PV-3dsmax/`. For each version: run the empirical
registry/service discovery (do NOT assume 2025's findings transfer), assemble a
single-file host config, and validate cold path + true-warm-boot path on a real fleet.

## Read these first (in order)

1. `PV-3dsmax/JOURNAL.md` — the complete 2025 run: every step, timing, failure, fix,
   and the current AWS resource state. The "Current state" section at top tells you
   what fleet/volumes exist right now.
2. `PV-3dsmax/DESIGN.md` — the three-layer design (system frameworks on C: / payload
   on volume via junctions / per-boot graft) and the open-questions list with statuses.
3. `PV-3dsmax/host-config/README.md` + `registry-subtrees.json` — graft format
   (.reg via `reg.exe export`/`import`, JSON only for services + state file) and the
   2025 subtree manifest.
4. `PV-3dsmax/REGISTRY-KEYS.md` — 2025's empirical registry findings (your baseline
   for diffing what 2026/2027 change).
5. `PV-3dsmax/SSM-ITERATION.md` — how to iterate on a live worker via the
   `ssh_to_smf_windows` job bundle, and the G1-G10 test-gap table.
6. `PV-3dsmax/host-config/3dsmax-2025-pv-cached.ps1` — the template you will adapt.
7. `PV-3dsmax/iteration/` — the exact scripts from the 2025 discovery run
   (04-before-fast, 07-after-diff, 09-build-graft, 10-teardown are the core four).

## AWS context

- Account `224071664257`, region `us-west-2`. Credentials: the user runs `update-ada`
  (alias for `ada credentials update --account 224071664257 --provider=isengard
  --role=Admin --once`). Verify with `aws sts get-caller-identity`.
- Farm `farm-fd8e9a84d9c04142848c6ea56c9d7568` (ProdUsWest). Debug queue:
  `queue-a928e259b15546df833ba209e8a50ca6` (MyQueue) with job attachments on
  `leongdldevbucket/DeadlineCloud`.
- A debug fleet may already exist (`PV3dsMaxDebugFleet`,
  `fleet-25060df816a4493a88dc41840a25fbd6`) — reuse or recreate from
  `PV-3dsmax/artifacts/create-fleet-payload.json`. Its volumes contain the 2025 caches;
  for 2026/2027 either create a fresh fleet (clean volume pool) or use
  `$FORCE_REINSTALL`/distinct state-file URIs so caches don't cross-contaminate.
- Installers: `s3://common-bealinerezpackage-resources-bucket/3dsmax/2026/3dsMax2026.zip`
  (5.9 GB) + `vray2026.exe` exist; **there is no `2027/` prefix as of 2026-08-04** —
  for 2027, follow the zip-creation guide in
  `deadline-cloud-samples/host_configuration_scripts/3dsmax/README.md` and upload to a
  bucket you can read. Access patterns in `PV-3dsmax/S3-INSTALLERS.md`.
- The local AWS CLI needed a newer Deadline model for `persistentVolumeConfiguration`;
  it is installed at `~/.aws/models/deadline/2023-10-12/service-2.json`. If missing,
  fetch from botocore GitHub (JOURNAL 23:46 entry).

## Method (per version — do 2026 first, then 2027)

1. **Debug fleet up**: Windows SMF, `persistentVolumeConfiguration` `{sizeGiB:500,
   mountPath:"D:"}`, on-demand, min/max 1, host config = the stock
   `deadline-cloud-samples/job_bundles/ssh_to_smf_windows/setup/host_config.ps1`
   (SSM enabler ONLY — the PV script does not fit alongside it; see trap T2).
2. **SSM session**: submit `ssh_to_smf_windows` via its `submit.sh` to MyQueue,
   extract the `mi-*` node from the session log (`PV-3dsmax/tools/get_node.sh`), run
   everything through `PV-3dsmax/tools/ssm-run.sh <ps1> [timeout] [node]` (SSM
   RunCommand as SYSTEM).
3. **Layer-0 check**: verify the version's OS prerequisites on the AMI. 2025 needed
   only .NET Framework 4.8 (ships on Windows Server 2022). 2026/2027 may need .NET
   Desktop Runtime or newer VC++ — check Autodesk's system requirements page AND
   verify empirically (a missing runtime shows up as 3dsmaxbatch failing to start).
   Anything needed goes in the host config as an idempotent Layer-0 step on C:.
4. **BEFORE snapshot**: `reg.exe export` of `HKLM\SOFTWARE` + Services hive + Win32
   service JSON + machine env JSON (adapt `iteration/04-before-fast.ps1`). Never use
   a PowerShell per-key walk (trap T3).
5. **Junctions + install**: create the four junctions (adapt `iteration/05`; paths
   contain the version year), extract, `Setup.exe -q`, expect exit 0. Confirm payload
   landed on `D:` and note the install time.
6. **AFTER snapshot + diff** (adapt `iteration/07`): produce the added-keys list.
   Compare against `PV-3dsmax/REGISTRY-KEYS.md` — expect a different version key
   (2025 used `Autodesk\3dsMax\27.0`; 2026/2027 will be `28.0`/`29.0` — verify, don't
   assume), a different `ADSK_3DSMAX_x64_<year>` env var, and possibly changed
   service names/paths. **Document any delta from 2025 explicitly.**
7. **Build graft + teardown + graft + validate in-session** (adapt `iteration/09-13`):
   validation = env contract from a fresh process, `3dsmaxbatch.exe -help` exit 0,
   `AdskLicensingInstHelper.exe list` shows the 3DSMAX feature for the right version.
8. **Assemble the production script**: copy `host-config/3dsmax-2025-pv-cached.ps1`
   to `host-config/3dsmax-<year>-pv-cached.ps1`, update `$MAX_VERSION`, installer
   URI, any Layer-0 steps, any service-list delta, and any registry subtree delta.
   Keep it under 15,000 characters (trap T2). Update
   `host-config/registry-subtrees.json` with a per-version section.
9. **Validate the production script itself**: run its cold path on an empty volume
   via SSM (presigned-URL variant — see trap T6), then teardown + re-run to confirm
   auto-WARM.
10. **True warm boot**: set the fleet host config to the production script alone,
    cycle 0→1, and confirm from the worker's CloudWatch host-config log
    (`/aws/deadline/<farm>/<fleet>`, stream `worker-*`): `=== WARM boot ===` …
    `Total (warm graft)` under a minute, exit code 0. Mind the AZ trap (T5).
11. **Render test**: submit the minimal_test bundle
    (`PV-3dsmax/render-test/minimal_test_bundle`, adapted from
    `deadline-cloud-for-3ds-max/test/integ/test_scripts/minimal_test`) and compare
    outputs against `expected_images/` (frames 1-2 × TopCam/SideCam, 1280x720 jpg,
    tolerance 2 per the integ test). Requires the adaptor
    (`Install-Adaptor` step in the script) and MyQueue's job attachments.
12. **Journal every step** in `PV-3dsmax/JOURNAL.md` (append-only, keep "Current
    state" at top accurate) and save new scripts under `PV-3dsmax/iteration/` and
    docs under `PV-3dsmax/`. Scrub presigned URLs from anything you save.

## Known traps — all hit live during the 2025 run; do not rediscover them

- **T1 stderr under strict mode**: `reg.exe` and `pip`/`ensurepip` write benign
  messages to stderr; with `$ErrorActionPreference='Stop'` these become fake
  terminating errors. Wrap every such call: `cmd /c "tool args >nul 2>&1"`. robocopy:
  exit codes 0-7 are success; check `-ge 8` and then `cmd /c exit 0`.
- **T2 `hostConfiguration.scriptBody` hard limit = 15,000 chars**. The PV script and
  the SSM enabler cannot be chained in one host config. Debug fleet = SSM enabler;
  production validation = PV script only; verify via CloudWatch, not SSM.
- **T3 registry snapshots**: PowerShell per-key walks take 30+ min. `reg.exe export`
  of the full hive takes ~16 s; diff the exported key lines (streaming HashSet, ~6 s).
- **T4 SCM registration**: importing Services registry keys needs a reboot to take
  effect; host config cannot reboot. Re-register with `sc.exe create` from captured
  JSON (that's why services are JSON, not .reg).
- **T5 volumes pool per fleet+AZ, no AZ pinning exists**: a recycled worker may land
  in a different AZ and get an empty volume → COLD path. This is by design; the
  state-file check handles it. Expect to cycle more than once to land on a cached AZ.
- **T6 fleet role S3**: `BealineE2EFleetRole` has NO s3 permissions. For SSM-driven
  tests use presigned URLs (die with the session token — regenerate, never persist);
  for a long-lived fleet grant the role `s3:GetObject` and use `aws s3 cp`.
- **T7 FlexNet lives outside the junction set**
  (`C:\Program Files\Common Files\Macrovision Shared` + `C:\ProgramData\FLEXnet`):
  capture/restore by robocopy. Verify 2026/2027 didn't move it.
- **T8 licensing hygiene**: keep `Autodesk Access Service Host` registered but
  DISABLED on render workers. Watch `C:\ProgramData\Autodesk\CLM` (via the
  ProgramData junction) for machine-coupled entitlement state.
- **T9 dev-box shell**: long foreground commands have wedged; prefer background
  process execution for anything slow, and write helper loops to files (zsh heredoc
  multi-line loops misbehave).
- **T10 don't bake presigned URLs into saved files**: scrub before committing.

## Success criteria (each version)

1. Cold path: single-file script, `Setup.exe -q` exit 0 through junctions, capture
   written, state file valid, `3dsmaxbatch -help` OK. Time it.
2. True warm boot: fresh worker, CloudWatch shows WARM graft < 60 s, exit 0.
3. Licensing: `AdskLicensingInstHelper list` shows the right product version.
4. minimal_test render matches expected images (or, if the scene is 2025-authored and
   won't open in newer Max, document that and render a version-appropriate scene).
5. All deltas vs 2025 documented in `REGISTRY-KEYS.md` (new section per version) and
   `registry-subtrees.json`.
6. Journal updated; fleet scaled to 0 when done; no presigned URLs left in files.

## Status update (2026-08-04 ~19:00 UTC): 2025 AND 2026 ARE DONE

Both versions are complete and render-validated — see JOURNAL.md from "S3 SNAPSHOT
TIER" onward. What exists now:
- Gen-2 architecture (S3-first, PV accelerator): `host-config/3dsmax-2026-s3-cached.ps1`
  deployed via `bootstrap-host-config-2026.ps1` on fleet PV3dsMax2026Fleet
  (`fleet-6a12c81636e442439541dc5c3c7a19dd`). 2025 equivalent on the original fleet.
- S3 cache prefixes: `s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-{2025,2026}/`
  each with `host-config.ps1`, `pv-payload.zip`, `installers/`.
- All paths render-validated pixel-perfect (minimal_test): 2025 cold/PV-warm/S3-warm,
  2026 cold (+ S3-warm cycle — check JOURNAL for its result).
- Open q12 resolved: minimal registry graft is render-sufficient.

**Remaining work for a follow-up agent: 3ds Max 2027 only** (and any renderer plugin
layers). For 2027: no installer exists in the shared bucket — build the zip per
`deadline-cloud-samples/host_configuration_scripts/3dsmax/README.md`, stage it under
`pv-cache/3dsmax-2027/installers/`, copy `3dsmax-2026-s3-cached.ps1` → 2027 (change
CONFIG block only), upload, new bootstrap, new fleet or repoint an existing one.
Method below remains the reference for the discovery pass if 2027's installer
behaves differently (new services, new .NET requirements, junction refusal).
- `added-software-keys.txt` (complete 2025 key list) was on the az3 discovery volume —
  since deleted volumes only persist ~TTL, check `aws deadline list-volumes` before
  assuming it still exists; the distilled findings are all in REGISTRY-KEYS.md.
