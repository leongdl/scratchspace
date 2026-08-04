# 3ds Max 2025 Registry Keys — discovered on Windows Server 2022 SMF (2026-08-04)

Source: before/after full-hive `reg.exe export` diff around a real `Setup.exe -q` install
(see `JOURNAL.md` entries 00:51-01:50 and `iteration/04`, `iteration/07`, `iteration/09`).
This answers the open question from PR #173 ("which Autodesk registry keys are required?").

## Raw numbers

| Hive | Keys before | Keys after | Added |
|---|---|---|---|
| `HKLM\SOFTWARE` | 337,042 | 366,585 | **29,543** |
| `HKLM\SYSTEM\CurrentControlSet\Services` | 2,885 | 2,890 | 5 (3 services + subkeys) |

## Added-key breakdown (top prefixes, from the diff)

| Count | Prefix | Graft? |
|---|---|---|
| 25,415 | `HKLM\SOFTWARE\Microsoft\Windows` (Installer/servicing bookkeeping) | **NO** — render path doesn't need it; importing invites servicing operations |
| 2,053 | `HKLM\SOFTWARE\Classes\CLSID` | yes (iteration graft; see note below) |
| 617 | `HKLM\SOFTWARE\Classes\Interface` | yes (iteration graft) |
| 267 | `HKLM\SOFTWARE\Wow6432Node\Classes` | yes (iteration graft) |
| 267 | `HKLM\SOFTWARE\Classes\WOW6432Node` | yes (iteration graft) |
| 203 | `HKLM\SOFTWARE\Autodesk\3dsMax` (incl. `\27.0`) | **YES — core** |
| 131 | `HKLM\SOFTWARE\Classes\TypeLib` | yes (iteration graft) |
| 102 | `HKLM\SOFTWARE\Classes\Installer` | no (installer bookkeeping) |
| 52 | `HKLM\SOFTWARE\Classes\Record` | yes (iteration graft) |
| 47 | `HKLM\SOFTWARE\Wow6432Node\Autodesk` | **YES — core** |
| 12 | `HKLM\SOFTWARE\Autodesk\UPI2` | YES (part of Autodesk subtree) |
| 12 | `HKLM\SOFTWARE\Wow6432Node\Microsoft` | no |
| 7 | `HKLM\SOFTWARE\Wow6432Node\dotnet` | no (runtime already on AMI) |
| 6 | `HKLM\SOFTWARE\Autodesk\ADSKPrismTextureLibraryNew` | YES (Autodesk subtree) |
| 5 | `HKLM\SOFTWARE\Autodesk\Reg`, `\ObjectDBX` | YES (Autodesk subtree) |
| 4 ea | `Classes\3dsmax`, `3dschr`, `3dsifl`, `3dsms`, `3dsmxp`, `3dsmcr` | **YES — file associations** |
| 3 | `Classes\.max` | **YES** |
| 3 | `HKLM\SOFTWARE\Autodesk\PLM` | YES (Autodesk subtree) |
| misc | `Classes\AcSmComponents.*`, `AcSignCore.*`, `ADDFLOW.*`, `MaxInventorServerHost.*` | yes (iteration graft) |

## Services created by the installer

| Service | StartMode | Binary path | Junctioned? |
|---|---|---|---|
| `AdskLicensingService` | Auto | `C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingService\AdskLicensingService.exe` | yes (AutodeskSharedX86 junction) |
| `FlexNet Licensing Service 64` | Auto | `C:\Program Files\Common Files\Macrovision Shared\FlexNet Publisher\FNPLicensingService64.exe` | **NO — outside junction set; captured/restored by robocopy** (`D:\Software\MacrovisionShared`, `D:\SoftwareData\FLEXnet`) |
| `Autodesk Access Service Host` | Auto | `C:\Program Files\Autodesk\AdODIS\V1\Setup\AdskAccessServiceHost.exe` | yes (Autodesk junction) — **policy: keep registered but DISABLED on render workers** |

Warm-boot service restore is done with `sc.exe create` from captured JSON (immediate SCM
registration; importing the Services .reg alone would need a reboot).

## Machine environment variables set by the installer

- `ADSK_3DSMAX_x64_2025 = C:\Program Files\Autodesk\3ds Max 2025\` (created)
- `Path` (modified)

The graft additionally applies the PR #173 contract every boot:
`3DSMAX_EXECUTABLE`, `ADSK_3DSMAX_BATCH_EXE`, `ADSK_3DSMAX_EXECUTABLE`,
`ADSK_3DSMAX_LOCATION`, `ADSK_3DSMAX_VERSION`, `PYTHONPATH`, `Path`.

## Two graft variants exist

1. **Iteration graft** (on the az3 volume, built by `iteration/09`): single
   `autodesk-graft.reg` = full Autodesk subtrees + ALL 29,543 added keys minus
   `SOFTWARE\Microsoft\*` → **4,125 keys, 1.3 MB**. Includes the ~3k COM
   CLSID/Interface/TypeLib registrations. Validated: 3dsmaxbatch + licensing helper.
2. **Production graft** (on the az2 volume, built by the single-file host config):
   `reg.exe export` of `HKLM\SOFTWARE\Autodesk`, `HKLM\SOFTWARE\Wow6432Node\Autodesk`,
   plus `Classes\{3dsmax,3dschr,3dsifl,3dsms,3dsmxp,3dsmcr,.max}` → 9 .reg files.
   Excludes the bulk COM registrations. Validated: 3dsmaxbatch -help on a true warm
   boot. **Open question 12:** whether real renders need the COM set; if so, the cold
   path must adopt the before/after diff capture from the iteration scripts.

## Where the full artifacts live

On the persistent volumes (attach a worker to read):
- az2 `volume-40042c1cbc9f4a068f68919d07e93ebd`: production layout
  (`D:\SoftwareRegistry\graft\*.reg`, `graft\services\*.json`) + also the earlier
  snapshots taken on this volume.
- az3 `volume-5bef90e3d0ad4ecdb45a868794e49da9`: iteration layout
  (`D:\SoftwareRegistry\snapshots\before-*/after-*` full-hive exports,
  `added-software-keys.txt` — the complete 29,543-key list, `added-service-keys.txt`,
  `graft\autodesk-graft.reg`).

The full-hive exports are ~183 MB each and were not copied off-box; the complete
added-key list (`added-software-keys.txt`, ~2 MB) is worth pulling next time a worker
has the az3 volume + an SSM session.
