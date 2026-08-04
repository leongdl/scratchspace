# PV-3dsmax Final Results

**Date:** 2026-08-04 · **Farm:** ProdUsWest (224071664257, us-west-2)

Final state: everything render-validated **pixel-perfect** against the repo's expected
images (`deadline-cloud-for-3ds-max` minimal_test, 4 tasks: frames 1–2 × TopCam/SideCam,
Scanline 1280×720, tolerance 2 — all matched with `max_diff = 0.00`).

## Boot-path scorecard

| Version | Cold (once per version, farm-wide) | S3-warm (fresh volume, any AZ) | PV-warm |
|---|---|---|---|
| **3ds Max 2025** | 13–26 min | 3:34 | 0:15 |
| **3ds Max 2026** | ~39 min incl. zip publish | 4:46 | same mechanism |

## Capstone proof

The last cycle proved the interesting case: a brand-new worker on an empty volume
pulled the corrected 6.5 GB zip from S3, restored the payload **including the .NET
runtime**, grafted registry and services, passed the hardened self-test in
**4 minutes 46 seconds**, and rendered all 4 tasks with **zero pixel difference**.

## Validation evidence (job IDs)

| Path exercised | Job | Result |
|---|---|---|
| 2025 cold-installed worker | `job-82b4f07b310f4144b7a5459be347a68f` | 4/4, all match |
| 2025 PV-warm grafted worker | `job-e9cd8292d8724923a74e267e3a111bdd` | 4/4, all match |
| 2025 S3-warm restored worker | `job-83c50a2c60de445f9ab759c3330c3666` | 4/4, all match |
| 2026 cold (post .NET fix) | `job-927381f86fde4f6d803afe4203d3cd3f` | 4/4, all match |
| 2026 S3-warm restored (capstone) | `job-efb65054c70148c895a37ce67216fcbd` | 4/4, all match |

## Architecture (gen-2, S3-first)

```
PV-WARM   volume already has payload + valid state  -> junction + graft      ~15 s
S3-WARM   farm-global zip in S3                     -> download + extract
          (works with or without a PV)                 + graft               ~3-5 min
COLD      neither                                   -> token-guarded install
          (happens once per version, farm-wide)        + capture + publish   ~15-40 min
```

- Payload zip = `Software\` + `SoftwareData\` + `SoftwareRegistry\` (registry .reg
  captures, service JSON, licensing files) + `.install-state.json`.
- Concurrency: 1-object `installing.token` claimed atomically via S3 conditional write
  (`put-object --if-none-match '*'`); stale tokens (crashed installer) taken over.
- Deployed via a ~900-char bootstrap in the fleet `scriptBody` (15,000-char limit)
  that fetches the real script from S3.

## Key version delta discovered

3ds Max **2026 requires the .NET Desktop Runtime**, which ODIS installs to
`C:\Program Files\dotnet` — *outside* the junction set. Cold workers had it; restored
workers crashed at scene init ("Terminating due to required .NET Core version not
present") while `3dsmaxbatch -help` still passed. Fix: capture/restore dotnet like
FlexNet, and self-test with `dotnet --list-runtimes` at boot.

## End state

- Both fleets (`PV3dsMaxDebugFleet`, `PV3dsMax2026Fleet`) scaled to 0/0.
- S3 cache: `s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-{2025,2026}/`
  (`pv-payload.zip` 5.96 / 6.54 GB, `host-config.ps1`, `installers/`).
- Remaining volumes reaped by 168 h TTL; `PvCacheS3Access` inline policy remains on
  `BealineE2EFleetRole` (scoped, reversible).
- Full step-by-step record: `JOURNAL.md`. 2027 handoff: `PROMPT-3dsmax-2026-2027.md`.
