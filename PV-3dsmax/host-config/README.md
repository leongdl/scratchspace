# host-config

Production host configuration script for 3ds Max 2025 with persistent-volume caching,
plus the registry manifest that documents what the script captures and replays.

| File | What it is |
|---|---|
| `3dsmax-2026-s3-cached.ps1` | **Gen-2, current recommended.** S3-first architecture: farm-global S3 payload zip is the primary cache (token-guarded single cold install per version, works with or without a persistent volume — cache root falls back to `C:\DeadlineCache`); the PV is an accelerator on top. Render-validated on 3ds Max 2026. |
| `3dsmax-2025-pv-s3-cached.ps1` | Gen-1.5: same two tiers for 3ds Max 2025, PV-first framing. All three paths render-validated (PV-warm 0:15, S3-warm 3:34, cold 13-26 min). |
| `bootstrap-host-config.ps1` / `-2026.ps1` | ~900-char stubs deployed as the fleet's actual `scriptBody` (15,000-char limit): fetch the real script from S3 and run it. |
| `3dsmax-2025-pv-cached.ps1` | Gen-1: single-file PV-only variant (fits inline in `scriptBody`, no S3 tier). Kept for fleets without S3 role grants. |
| `registry-subtrees.json` | Machine-readable manifest of every registry subtree, service, and env var the graft covers — with counts from the empirical install diff. |
| `README.md` | This file: format and mechanism explainer. |

## Registry graft: format and mechanism

**Format: Windows `.reg` files (Registry Editor 5.00, UTF-16LE), not JSON.**
JSON is used for exactly two things:

1. **Service definitions** (`graft\services\*.json`) — name, display name, binary path,
   start mode. These are JSON because the warm boot re-registers services with
   `sc.exe create` for immediate Service Control Manager visibility. Importing a
   service's registry key via .reg alone works, but SCM does not see the service until
   the next reboot — and host config cannot reboot the worker. This mirrors the
   After Effects sample's `Export-InstallerState`/`Import-InstallerState` pattern.
2. **State file** (`D:\.install-state.json`) — version + installer URI, used to decide
   warm vs cold and to invalidate the cache when the configured installer changes.

**Why values are not checked into this repo:** the .reg contents are produced by the
real installer at cold-install time (product GUIDs, per-machine config). The design is
*capture, don't enumerate* — a hand-maintained key list drifts every Max release, which
is exactly the failure mode PR #173 hit. The repo carries the authoritative *subtree
list* (`registry-subtrees.json`); the volume carries the captured values.

### Cold path (capture) — `Export-InstallerState`

```powershell
# Full Autodesk subtrees (values included), native format, ~seconds:
reg.exe export "HKLM\SOFTWARE\Autodesk"             "$GRAFT\hklm-autodesk.reg"     /y
reg.exe export "HKLM\SOFTWARE\Wow6432Node\Autodesk" "$GRAFT\hklm-wow-autodesk.reg" /y
# File associations 3ds Max registers under Classes:
#   3dsmax 3dschr 3dsifl 3dsms 3dsmxp 3dsmcr .max  ->  cls-*.reg
# Services -> JSON (for sc.exe create)
# FlexNet payload (OUTSIDE the junction set) -> robocopy to the volume
```

### Warm path (replay) — `Import-InstallerState`

```powershell
foreach ($regFile in Get-ChildItem "$GRAFT\*.reg") {
    Invoke-Reg "import `"$($regFile.FullName)`""     # wraps: cmd /c "reg.exe import ... >nul 2>&1"
}
# then: sc.exe create per services\*.json, robocopy FlexNet back, env contract, self-test
```

The `cmd /c ... >nul 2>&1` wrapper is load-bearing: `reg.exe` (and `pip`) write benign
messages to **stderr**, which `$ErrorActionPreference = 'Stop'` converts into fake
terminating errors. Both bit us live (JOURNAL 01:40 and 03:17). Rule: in host-config
strict mode, every native tool with benign stderr output must have its streams
contained (`reg.exe`, `pip`, `ensurepip`) or its exit-code policy handled (`robocopy`
codes 0-7 are success).

## Two graft variants (see `registry-subtrees.json` and `../REGISTRY-KEYS.md`)

- **Production** (az2 volume): Autodesk subtrees + 7 file-association classes = 9 .reg
  files. Small and reviewable. Validated by `3dsmaxbatch -help` + licensing helper on a
  true warm boot; NOT yet validated by a full scene render (open question 12 — the
  ~3,100 COM CLSID/Interface/TypeLib keys are omitted).
- **Iteration** (az3 volume): single `autodesk-graft.reg` (4,125 keys, 1.3 MB) built by
  diffing full-hive before/after exports and keeping everything the installer added
  except `HKLM\SOFTWARE\Microsoft\*`. The superset fallback if renders need COM.

## Pulling the captured .reg files off a volume

Attach a worker (SSM debug fleet config), then:

```powershell
Compress-Archive D:\SoftwareRegistry\graft C:\graft.zip
# copy off via S3 presigned PUT, or read small files inline over SSM RunCommand
```
