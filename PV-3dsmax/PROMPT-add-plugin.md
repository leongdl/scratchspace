# Agent prompt: add a renderer/plugin to the cached 3ds Max host config

Copy everything below the line into a fresh agent session in the repo containing
`PV-3dsmax/` (with `deadline-cloud-samples/` cloned as a sibling for reference).

---

## Mission

Add a plugin (V-Ray, Corona, tyFlow, Forest Pack/RailClone/AEC, or similar) to the
**cached** 3ds Max host configuration (`PV-3dsmax/host-config/3dsmax-2026-s3-cached.ps1`
architecture: S3 payload zip primary tier, persistent volume accelerator, token-guarded
single cold install). The plugin must survive all three boot paths — COLD, S3-WARM,
PV-WARM — and be proven with a render that actually exercises the plugin.

Adding a plugin to the plain (uncached) scripts is a solved problem; your job is the
*cache integration*. The difference: a plain script installs on every boot, so nothing
needs to be captured or replayed. In the cached script, the installer runs ONCE
(cold path), and every other worker gets the plugin via zip restore + graft — so every
side effect of the plugin installer (files, registry, services, licensing, env) must
be either junction-covered, captured-and-replayed, or re-applied per boot.

## Reference material (read in this order)

1. `PV-3dsmax/host-config/3dsmax-2026-s3-cached.ps1` — the gen-2 script you are
   extending. Understand `Export-InstallerState` / `Import-InstallerState` /
   `Invoke-Graft` / `Publish-S3Zip` / `Test-StateValid` before touching anything.
2. `deadline-cloud-samples/skills/3dsmax-host-config/add-ons/*.md` — self-contained
   building blocks per plugin (vray.md, corona.md, tyflow.md, aec-plugins.md):
   silent-install flags, install directories, env vars, licensing setup.
3. `deadline-cloud-samples/host_configuration_scripts/3dsmax/3dsmax-20XX-and-<plugin>/`
   — working plain-install scripts. Lift the exact installer invocations from here
   (e.g. V-Ray: `-gui=0 -configFile=... -quiet=1` with a `DefValues` XML; Corona:
   `-gui=0 -auto`; Forest Pack/RailClone: exe installers + loose .dlm/.dlt files into
   `$MAX_ROOT\plugins`).
4. `PV-3dsmax/JOURNAL.md` traps T1–T10 + the two live lessons that will bite you here:
   - **tar/`-C` paths**: forward slashes, never a trailing `\"` (2026-08-04 19:45).
   - **Out-of-junction payloads**: 3ds Max 2026's .NET runtime landed on C: outside
     the junctions; cold workers fine, restored workers dead. Plugins WILL do this
     too (license services, Common Files, ProgramData outside Autodesk).
5. `PV-3dsmax/REGISTRY-KEYS.md` + `host-config/registry-subtrees.json` — what the
   base capture already covers.

## The seven integration points

Work through each one explicitly for your plugin; this checklist IS the deliverable
structure. Use the V-Ray column as the worked example.

| # | Integration point | What to do | V-Ray example |
|---|---|---|---|
| 1 | **CONFIG + state file** | Add `$<PLUGIN>_INSTALLER_S3_URI` (+ version var). Extend `Write-StateFile`/`Test-StateValid` with the plugin name+installer basename so changing the plugin version invalidates BOTH the volume cache and forces a new zip. Bump the S3 prefix (e.g. `.../3dsmax-2026-vray/`) so plugin and plugin-less fleets don't share a zip. | `vray_adv_max2026.exe`, state gains `renderer: vray, rendererInstaller: ...` |
| 2 | **Junctions** | Map every directory the installer writes. Add junctions for payload roots not already covered. Already covered: `C:\Program Files\Autodesk`, `C:\ProgramData\Autodesk` (incl. `ApplicationPlugins\VRay3dsMax*`), both `Autodesk Shared`. | Add `C:\Program Files\Chaos -> $SW\Chaos` |
| 3 | **Cold install** | In the cold path, AFTER `Install-3dsMax`: download installer to `$CACHE_ROOT\installers`, run the silent install (exact flags from the add-on/plain script), through the junctions. | DefValues config.xml + `-gui=0 -configFile -quiet=1`; disable cloud licensing via `setvrlservice.exe -cloud-server=0` |
| 4 | **Capture** (`Export-InstallerState`) | Registry: add the vendor subtrees (`reg.exe export`). Services: add names to `$ServiceNames`. **Out-of-junction discovery is mandatory**: take a `reg.exe export` + `Get-CimInstance Win32_Service` + filesystem snapshot before/after the plugin install on the first cold run (method: `PV-3dsmax/iteration/04+07`) and robocopy-capture anything on C: outside the junctions (the FlexNet/.NET pattern). | `HKLM\SOFTWARE\Chaos Group` + Wow6432Node; Chaos license service (vrlservice); check `C:\Program Files\Common Files\ChaosGroup` |
| 5 | **Graft/per-boot** (`Import-InstallerState` + env) | Restore captured payloads, import .reg, `sc.exe create` services. Licensing **config files are written fresh EVERY boot, never cached** (server changes must not invalidate the cache) — e.g. `vrlclient.xml`. Add the plugin env vars to `Set-EnvContract` (every boot; machine env is fresh). | `VRAY_FOR_3DSMAX2026_MAIN/_PLUGINS`, `VRAY_MDL_PATH_3DSMAX2026`, `VRAY_AUTH_CLIENT_FILE_PATH` -> dir containing vrlclient.xml |
| 6 | **Self-test** (`Test-Render`) | `-help` catches nothing plugin-related (the .NET lesson). Minimum: assert the plugin's DLLs exist at their load path after graft. Better: keep boot fast and rely on the render validation in #7, but fail loudly if payload dirs are empty. | `Test-Path "C:\ProgramData\Autodesk\ApplicationPlugins\VRay3dsMax2026\bin\vray*.dll"` |
| 7 | **Zip** (`Publish-S3Zip`) | Junctioned payloads are included automatically. Add any robocopy-captured out-of-junction dirs to the tar list if you put them outside `Software\`/`SoftwareData\`. Stop the plugin's license service around archiving (add to the stop list). | Chaos service in the stop-list |

## Validation protocol (all three paths, with a plugin-exercising render)

A Scanline render proves nothing about the plugin. Use a scene that requires it:

- **V-Ray**: `deadline-cloud-samples/host_configuration_scripts/3dsmax/3dsmax-2025-and-vray/sunflower_sphere/`
  is a ready-made job bundle (submit with `deadline bundle submit`, compare output).
- Corona/tyFlow/AEC: create or obtain a minimal scene using the plugin; validate the
  render completes without watermark/missing-plugin warnings in the session log.

Sequence (mirror the 2025/2026 runs in JOURNAL.md):
1. Deploy via bootstrap to a debug fleet, cycle → **COLD**: verify install order
   (Max, then plugin), capture lines in the log, zip published, render passes.
2. Delete the S3 zip? No — delete the **volume**, cycle → **S3-WARM**: restore, graft,
   render passes. This is the path that exposes every missed capture.
3. Cycle again without deleting anything → **PV-WARM**: graft, render passes.
4. Only then update `registry-subtrees.json` (new subtrees/services), `REGISTRY-KEYS.md`
   (new discovery section), JOURNAL.md (timings), and re-run any UBL/licensing check
   the plugin needs (V-Ray UBL vs license server: `port@host` variants in the add-on docs).

## Environment facts (as of 2026-08-04)

- Account 224071664257, us-west-2, farm `farm-fd8e9a84d9c04142848c6ea56c9d7568`.
  Fleets `PV3dsMaxDebugFleet` (2025) / `PV3dsMax2026Fleet` (2026), both scaled 0/0;
  MyQueue `queue-a928e259b15546df833ba209e8a50ca6` has job attachments configured.
- S3 cache: `s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-{2025,2026}/`;
  fleet role has `PvCacheS3Access` scoped to `DeadlineCloud/pv-cache/*` — plugin
  installers go under the same prefix (`.../installers/`).
- Plugin installers: check `s3://common-bealinerezpackage-resources-bucket/` first
  (`vray/`, per-version prefixes — see `PV-3dsmax/S3-INSTALLERS.md`); stage a copy
  into the pv-cache prefix with `--copy-props none`.
- Licensing: SMF UBL worked for 3ds Max out of the box; V-Ray/Corona UBL vs custom
  license server is a CONFIG decision — see the add-on docs and the Corona plain
  script's `vrlclient.xml` (127.0.0.1:30304 = UBL proxy pattern).
- No SSM on bootstrap-configured fleets: debug via the worker CloudWatch log
  (`/aws/deadline/<farm>/<fleet>`, stream `worker-*`), or temporarily swap the fleet
  host config to the SSM enabler (`PV-3dsmax/SSM-ITERATION.md`) for interactive work.

## Definition of done

1. All seven integration points addressed and documented in the script's comments.
2. COLD, S3-WARM, PV-WARM each render-validated with a plugin-exercising scene.
3. Version bump test: change the plugin installer URI in CONFIG → next boot goes COLD
   and publishes a new zip (state-file invalidation works for the plugin).
4. Docs updated (registry-subtrees.json, REGISTRY-KEYS.md, JOURNAL.md), fleet scaled
   to 0/0, no presigned URLs in committed files.
