# 3ds Max on Deadline Cloud SMF: Persistent Volume Caching Design

Combines two ideas from `deadline-cloud-samples`:

1. The **After Effects persistent volume caching pattern**
   (`host_configuration_scripts/aftereffects/aftereffects_redgiant/install-software.ps1`):
   junction-based install-once-to-volume with restore-on-boot, service snapshot/replay,
   and per-boot machine env var re-application.
2. The **runtime contract from PR #173** (`aws-deadline/deadline-cloud-samples#173`,
   conda recipes for 3ds Max 2025 + Corona): the `ADSK_3DSMAX_*` environment variable set,
   `CORONA_3DSMAX_<year>_LOAD_PATH`, and adaptor installation into the bundled Python.

Goal: use host configuration to install .NET and other system frameworks on every boot
(cheap, unjunctionable), but move the expensive 3ds Max + renderer installation to a
persistent volume. When the volume already carries a valid install, skip the installers
and **graft** the service registry, Windows registry, and environment contract back onto
the fresh C: drive.

Folder contents:

| File | Purpose |
|---|---|
| `DESIGN.md` | This design plan, milestones, and open questions |
| `SSM-ITERATION.md` | How to iterate on a live PV-mounted worker via SSM before committing to a host config, plus the test-gap analysis |
| `tools/registry-snapshot.ps1` | Before/after registry + service snapshot, diff, export, and apply tool used for discovery and warm-boot replay |

---

## Why the naive approaches fall short

**Host-config-only (today's `3dsmax-20XX-*.ps1` scripts):** every worker boot pays the
full download + `Setup.exe -q` cost, ~15-20 minutes per PR #173's own numbers.

**Conda-repackaging (PR #173):** fast, but three unresolved review threads identify what a
zipped file tree cannot carry:

- **Registry keys.** Internal prototypes needed Autodesk registry keys for 3ds Max to work
  properly under conda; the exact keys were never recovered (thread on
  `conda_recipes/3dsmax-2025/README.md`, never resolved).
- **`AdskLicensingService`.** A repackaged tree does not install or register the Autodesk
  licensing service.
- **Adaptor freshness.** Baking `deadline-cloud-for-3ds-max` into an archive pins it at
  archive-creation time and loses the runtime-upgrade path from the Deadline conda channel.

The key insight from the AE script (its own comment): **"C: registry is fresh each boot."**
The persistent volume carries files. It does not carry the registry, Windows services, or
machine environment variables. Those must be re-applied on every boot.

The combined design keeps a *real* installer run on the cold path (so registry keys and
services are created authoritatively by the vendor installer), captures the result to the
volume, and replays it on warm boots.

---

## Three layers, organized by cost vs cacheability

### Layer 0 — System frameworks. On C:, every boot, cheap.

- .NET Framework 4.8 **verification** (Windows Server 2022 ships it; this is a check, not
  an install — per the resolution of the .NET thread on PR #173)
- .NET Desktop Runtime, if the target Max version requires it
- VC++ redistributables
- Fonts, codecs, other side-by-side components

These write into WinSxS / System32 / the GAC and are not safely junctionable. Each step is
idempotent and skip-if-present. Target: under one minute.

### Layer 1 — Expensive payload. On the persistent volume, once.

- 3ds Max install tree (~7-10 GiB)
- Renderer payload (Corona or V-Ray)
- Autodesk Shared components
- Bundled Python with `pywin32` + `deadline-cloud-for-3ds-max`

Written by the real `Setup.exe -q` running **through the junctions**, so the vendor
installer does its normal work on what it believes is C:, and the volume captures the
result.

### Layer 2 — The graft. On C:, every boot, cheap.

- Re-point NTFS junctions
- `reg import` the captured registry subtrees
- Re-create and start Windows services from the JSON snapshot
- Re-set all Machine-scope environment variables
- Rewrite small licensing config files (`vrlclient.xml`)

---

## Boot flow

```
read DEADLINE_PERSISTENT_MOUNT (Machine scope)
  ├── empty ──────────────► Layer 0 + full install to C:  (today's behavior, unchanged)
  └── present
        ├── state file valid ──► Layer 0 + Layer 2 (graft)                        [warm]
        └── missing/stale ─────► Layer 0 + Layer 1 (install) + capture + Layer 2  [cold]
```

**Fallback:** if any graft step fails (junction target missing, `reg import` error,
licensing service refuses to start), invalidate the state file and fall through to a full
install rather than handing the fleet a broken worker.

---

## Junction set

Mirrors the AE script's `$junctions` array. `Initialize-Junctions` creates missing parents,
creates targets on cold boot, and re-points links on warm boot.

| Link on C: | Target on volume | Why |
|---|---|---|
| `C:\Program Files\Autodesk` | `$SW\Autodesk` | the application |
| `C:\ProgramData\Autodesk` | `$DATA\Autodesk` | ApplicationPlugins, per-machine config |
| `C:\Program Files\Common Files\Autodesk Shared` | `$SW\AutodeskShared` | shared components |
| `C:\Program Files (x86)\Common Files\Autodesk Shared` | `$SW\AutodeskSharedX86` | licensing components |
| `C:\Program Files\Chaos` | `$SW\Chaos` | V-Ray / Corona payload |

Rules:

- Junction the `Autodesk Shared` subdirectory, never the whole `Common Files` tree.
- `vrlclient.xml` under `C:\Program Files\Common Files\ChaosGroup` is a few bytes of
  licensing configuration. Write it fresh every boot rather than persisting it, so a
  license-server change takes effect without invalidating the volume.

Volume layout (matches AE conventions):

```
$MOUNT\
  Software\            ($SW)    junctioned Program Files targets
  SoftwareData\        ($DATA)  junctioned ProgramData targets
  SoftwareServices\    ($SVC)   service definition JSON snapshots
  SoftwareRegistry\    ($REG)   exported .reg files + snapshot diffs
  .install-state.json           versioned state file (see below)
```

---

## Registry: capture, don't enumerate

This resolves the open PR #173 question ("which Autodesk registry keys?") without needing
the lost prototype: **snapshot the installer's actual output instead of maintaining a
hand-curated key list** that drifts every Max release.

### Instrumentation: before/after snapshots (debugging + discovery)

`tools/registry-snapshot.ps1` is run **before and after** the 3ds Max (and renderer)
installation, on cold installs and during all SSM iteration sessions:

1. `snapshot` walks `HKLM:\SOFTWARE` and `HKLM:\SYSTEM\CurrentControlSet\Services`
   recursively and emits one hashed line per key/value to a timestamped file. It also
   dumps the full `Win32_Service` table to JSON.
2. `diff` compares two snapshots and reports added / removed / modified keys and values,
   grouped by top-level prefix. This is the authoritative answer to "what did the
   installer actually touch."
3. `export` writes `reg.exe export` files for the vendor subtrees discovered in the diff.
4. `apply` replays those `.reg` files onto a fresh C: (the warm-boot graft step).

The `before`/`after` snapshot pair and the diff report are saved to
`$REG\snapshots\` on the persistent volume so every cold install leaves a debuggable
audit trail. When something breaks on a warm boot, diff the current registry against the
`after` snapshot to see exactly what the graft failed to restore.

### Production replay set (initial hypothesis, to be confirmed by M0 diffs)

- `HKLM\SOFTWARE\Autodesk`
- `HKLM\SOFTWARE\WOW6432Node\Autodesk`
- `HKLM\SOFTWARE\Chaos Group` / `HKLM\SOFTWARE\Chaos` (name varies by product version)
- Chaos WOW6432Node equivalents

Deliberately excluded:

- `CurrentVersion\Uninstall` entries — render workers never uninstall, and importing them
  invites Autodesk Access to attempt servicing operations.
- Machine-identity-coupled licensing state (see CLM note under Services).

---

## Services: generalize the AE snapshot/replay

The AE script's `Export-InstallerState` / `Import-InstallerState` filter on `*Red Giant*`.
Generalize the filter to Autodesk and Chaos service names:

| Service | Warm-boot handling |
|---|---|
| `AdskLicensingService` | re-create + start (the one PR #173's conda approach cannot provide) |
| `AdAppMgrSvc` (Autodesk Access) | re-create, leave **disabled** — render workers don't need it and it burns startup time |
| Chaos license service (`vrlservice.exe`) | re-create + start when V-Ray/Corona present |

Service binaries resolve through the junctions, so `sc.exe create` with the captured
`PathName` works on a fresh C:.

**CLM decision:** `AdskLicensingService` caches entitlement state under
`C:\ProgramData\Autodesk\CLM`, which the ProgramData junction would persist. Restoring
cached entitlements onto a *different* worker is a licensing-hygiene question.
Recommendation: **exclude or clear `CLM` on restore** and let the service re-acquire.
Slower by seconds, correct by construction.

---

## Environment variable contract (from PR #173, applied at Machine scope)

Job templates work unchanged whether the fleet is conda-based or PV-based:

```
3DSMAX_EXECUTABLE       -> ...\3dsmaxbatch.exe   (what the adaptor reads today)
ADSK_3DSMAX_BATCH_EXE   -> ...\3dsmaxbatch.exe
ADSK_3DSMAX_EXECUTABLE  -> ...\3dsmax.exe        (GUI, per the PR thread resolution)
ADSK_3DSMAX_LOCATION / ADSK_3DSMAX_ROOT / ADSK_3DSMAX_VERSION / ADSK_3DSMAX_PYTHON
ADSK_APPLICATION_PLUGINS / ADSK_3DSMAX_PLUGINS_ADDON_DIR
Path, PYTHONPATH
CORONA_3DSMAX_<year>_LOAD_PATH          (Corona fleets)
VRAY_FOR_3DSMAX<year>_MAIN / _PLUGINS / VRAY_MDL_PATH_3DSMAX<year>  (V-Ray fleets)
VRAY_AUTH_CLIENT_FILE_PATH
```

PowerShell has no leading-digit export restriction, so both the legacy
`3DSMAX_EXECUTABLE` and the `ADSK_*` pair are set — no adaptor hot-patch needed while
[deadline-cloud-for-3ds-max#190](https://github.com/aws-deadline/deadline-cloud-for-3ds-max/issues/190)
is open.

All env vars are re-applied on **every** boot (warm and cold) because the C: registry that
backs Machine env vars is fresh each boot.

---

## Adaptor freshness

Run `pip install --upgrade deadline-cloud-for-3ds-max` (bundled Python) on **every** boot,
not just cold. Small, network-bound, and it recovers the runtime-upgrade benefit the
conda-archive approach loses. The install lands in the volume-backed Python — fine as long
as volumes are per-worker (open question 1).

---

## State file, not a bare marker

The AE script writes a plain `.install-complete` timestamp, which cannot detect "the admin
changed the installer S3 URI." Use `$MOUNT\.install-state.json`:

```json
{
  "schemaVersion": 1,
  "maxVersion": "2025",
  "maxInstallerUri": "s3://.../3ds-max-2025.zip",
  "rendererName": "corona",
  "rendererVersion": "13",
  "rendererInstallerUri": "s3://...",
  "registrySnapshotBefore": "SoftwareRegistry/snapshots/before-....txt",
  "registrySnapshotAfter": "SoftwareRegistry/snapshots/after-....txt",
  "installedAt": "..."
}
```

Any mismatch against the script's configured values invalidates the cache and triggers a
fresh install. A `$FORCE_REINSTALL` switch at the top of the script allows manual
invalidation.

---

## Deliverable shape

Host configuration is a single script pasted into the fleet console, so all helpers stay
inline in one `.ps1` — the same constraint the AE script lives under. Following the
`3dsmax-host-config` skill's conventions:

```
host_configuration_scripts/3dsmax/3dsmax-2025-corona-pv-cached/
  3dsmax-2025-corona-pv-cached.ps1
  README.md
```

Skill conventions preserved: one full S3 URI variable per installer marked `# TODO`, the
zip-creation guide link on the 3ds Max installer variable, install-then-configure
ordering, `Exit 0` at the end, fleet timeout 3600s (the cold path still needs it).

Optional later bridge: a tiny `3dsmax-locator` conda package that only exports the
`ADSK_*` variables pointed at the PV path, so job bundles stay identical across conda
fleets and PV fleets.

---

## Iteration plan

Iteration happens on a live PV-mounted fleet via SSM **before** any of this is committed
to a host configuration script. See `SSM-ITERATION.md` for the full workflow and the
test-gap analysis.

- **M0 — Instrumentation.** SSM into a PV worker. Run a cold install manually with
  per-phase timing and `registry-snapshot.ps1` before/after. The diff answers which
  Autodesk/Chaos keys and services matter. Everything downstream depends on this.
- **M1 — Volume install + graft, no renderer.** Junctions, env vars, state file.
  Validate with `3dsmaxbatch.exe -help` and a trivial render.
- **M2 — Registry and service replay.** Tear down C: state in-session, `apply` the
  exported `.reg` files, re-create services, confirm licensing acquires. Then confirm on
  a *true* warm boot by cycling the worker with the volume reattached.
- **M3 — Renderer payload.** Corona 13 (aligns with PR #173) or V-Ray
  (`sunflower_sphere` test bundle already exists).
- **M4 — Adaptor upgrade-on-boot** plus an end-to-end Deadline job submission.
- **M5 — Hardening.** Measure warm vs cold timing, test invalidation by bumping an
  installer URI, test the graft-failure fallback, then transcribe the proven steps into
  the single-file host config and validate it on a fresh fleet.

---

## Explicit caveats

- The junction pattern is proven for Adobe by the AE script, **not for Autodesk** —
  3ds Max is more registry-dependent, and M0 exists to find out how much.
- The specific Autodesk registry paths and service names above are a starting hypothesis
  from prior knowledge of Autodesk layouts, not something verified in this repo. M0's
  snapshot diffs confirm or correct them.

---

## Open questions

Statuses updated 2026-08-04 from the live iteration run (see `JOURNAL.md` for evidence).

1. **ANSWERED — per-worker.** Volumes attach to one worker at a time and are pooled per
   fleet + Availability Zone (docs + `VolumeSummary.attachedWorkerId`). No concurrent
   write hazard. BUT see new question 11: AZ scoping fragments the cache.
2. **DECIDED — 3ds Max 2025** first (installer available in the shared bucket; aligns
   with PR #173). Renderer not yet added; V-Ray 2025 exe is in the same bucket prefix.
3. **ANSWERED — yes.** `DEADLINE_PERSISTENT_MOUNT=D:` confirmed at Machine scope before
   jobs run; docs state it's available to host configuration scripts.
4. **ANSWERED — yes.** Volume detached to `AVAILABLE` on scale-to-zero and survived;
   `lastUsedTtlHours` (default 168h) reaps unused volumes.
5. **OPEN — UBL vs license server.** Iteration validated `AdskLicensingInstHelper list`
   registration survives the graft; an actual licensed render hasn't run yet.
6. **ANSWERED — yes.** ODIS `Setup.exe -q` exit 0 in 14:36 through all four junctions;
   payload landed on D:. No fallback needed.
7. **ANSWERED for base 3ds Max 2025 — no reboot needed.** `3dsmaxbatch.exe` validated
   immediately after install and after graft without any reboot.
8. **ANSWERED — walk is too slow, export is fast.** PowerShell per-key walk exceeded 25
   minutes (cancelled). `reg.exe export` of the full hives takes ~16-18 s; streaming
   key-set diff of before/after exports takes ~6 s. Production captures only vendor
   subtrees (1.3 MB graft file).
9. **OPEN — `job-user` ACL traversal.** All iteration ran as SYSTEM. Must validate a
   render as `job-user` through the junctions before M1 sign-off.
10. **OPEN — `3dsmax-locator` conda bridge.** Deferred.
11. **LARGELY RESOLVED by the S3 snapshot tier (2026-08-04).** Volumes pool per
    fleet+AZ with no AZ pinning, but the second cache tier removes the per-AZ cold
    install: the first cold worker zips {Software, SoftwareData, SoftwareRegistry,
    .install-state.json} to S3 (token-guarded via conditional PutObject so concurrent
    cold workers don't duplicate work); empty-volume workers restore from the zip in
    minutes. Boot ladder: PV-WARM (seconds) → S3-WARM (minutes, any AZ) → WAIT (poll
    for a concurrent installer's zip) → COLD (once ever per version). PV-WARM boots
    opportunistically seed the zip. See `host-config/3dsmax-2025-pv-s3-cached.ps1`
    and the bootstrap pattern that also removes the 15k scriptBody limit (T2).
    Residual cost note: idle cached volumes in other AZs still bill until
    `lastUsedTtlHours` reaps them.
12. **ANSWERED — minimal graft set is render-sufficient (2026-08-04).** Full Scanline
    renders via the adaptor passed pixel-perfect on workers whose registry came ONLY
    from the production graft (Autodesk subtrees + 7 file-association classes, no bulk
    COM keys) — on PV-warm, S3-warm, and for both Max 2025 and 2026. The iteration-
    style full-diff capture remains documented as the fallback for renderers/plugins
    that do register COM.
13. **NEW/OPEN — reg.exe stderr under strict mode.** `reg.exe` emits success text to
    stderr; under `$ErrorActionPreference='Stop'` + SSM this fabricates failures.
    Production script wraps all reg.exe calls in `cmd /c` (already applied in draft).
