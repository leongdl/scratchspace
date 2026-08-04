# artifacts

Evidence and exact-reproduction payloads from the live 2026-08-04 run. Nothing here
needs reverse engineering; each file is the real thing that was executed or produced.

| File | What it is |
|---|---|
| `create-fleet-payload.json` | The exact `aws deadline create-fleet --cli-input-json` payload that created PV3dsMaxDebugFleet (500 GiB PV at `D:`, on-demand Windows, min/max 1). Host config body elided — it's the stock `ssh_to_smf_windows/setup/host_config.ps1`. |
| `deployed-host-config-2025-with-adaptor.ps1` | The host config **as currently deployed on the fleet** (14,561 chars): production PV script + `Install-Adaptor` + the pip-stderr fix, with the installer download as presigned-URL `curl.exe` (URL scrubbed — this fleet's role has no S3 perms; regenerate per `../S3-INSTALLERS.md`). The repo master copy with `aws s3 cp` is `../host-config/3dsmax-2025-pv-cached.ps1`. |
| `last-graft-validation-output.json` | Raw SSM RunCommand invocation output of the iteration graft validation: env contract, `3dsmaxbatch -help` exit 0, `AdskLicensingInstHelper list` showing 3DSMAX 128Q1 2025.0.0.F. |
| `warm-graft-pip-stderr-failure.log.json` | CloudWatch worker-log events of the warm graft that failed because pip wrote a WARNING to stderr under strict mode (JOURNAL 03:17). Evidence for the stderr-containment rule. |

## Artifacts that live ONLY on the persistent volumes (not in this repo)

The captured registry values, full-hive snapshots, and the complete added-key list are
on the two EBS persistent volumes in the fleet's pool — **not in S3, not on this box**.
The cold path writes them to `D:` on the worker; the volume detaches with the files
inside. To retrieve: attach a worker (fleet must run the SSM-enabler host config, which
does NOT fit alongside the PV script in the 15k `scriptBody` limit — swap configs),
then copy off via SSM.

| Volume | AZ | Contents |
|---|---|---|
| `volume-40042c1cbc9f4a068f68919d07e93ebd` | usw2-az2 | Production-layout graft: `D:\SoftwareRegistry\graft\{hklm-autodesk.reg, hklm-wow-autodesk.reg, cls-*.reg, services\*.json}` + earlier snapshots |
| `volume-5bef90e3d0ad4ecdb45a868794e49da9` | usw2-az3 | Iteration-layout: `D:\SoftwareRegistry\graft\autodesk-graft.reg` (4,125 keys), `D:\SoftwareRegistry\snapshots\{before,after}-*-HKLM-SOFTWARE.reg` (~183 MB full-hive exports), **`added-software-keys.txt` (the complete 29,543-key list)**, `added-service-keys.txt` + a fresh 3ds Max install without state file (post buggy-script run) |

Worth pulling next time a session exists: `added-software-keys.txt` (~2 MB) and the
9 production .reg files (1-2 MB total) — attach them here under `artifacts/from-volume/`.
