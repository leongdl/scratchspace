# DCV Desktop Environment Options for GPU-Accelerated Containers

## Goal

Run a GPU-accelerated remote desktop inside a Docker container using Amazon DCV with DCV-GL enabled (OpenGL interception for GPU-accelerated rendering in the viewport).

## Constraints

- Docker container (no systemd/init)
- DCV virtual session mode (no physical display)
- DCV-GL must be ON for GPU-accelerated OpenGL
- Rocky Linux 9 + nvidia/cuda base image
- No `--privileged` flag (use minimal capabilities)

## Options Evaluated

### 1. XFCE (tested, works WITHOUT DCV-GL)

- Lightweight, no systemd dependency
- Works perfectly in containers with `--gl off`
- DCV-GL ON causes segfaults in all XFCE/GTK3 binaries (xfwm4, xfdesktop, xfce4-panel)
- Root cause: DCV-GL's LD_PRELOAD GL interception crashes GTK3 rendering
- Status: WORKING (gl off), FAILS (gl on)

### 2. GNOME (tested, fails in container)

- Requires systemd/logind — `gnome-session` exits immediately without it
- gnome-classic also fails (same logind dependency)
- Would need `--privileged` + `/usr/sbin/init` as entrypoint (heavy, anti-pattern)
- DCV-GL does NOT crash GNOME binaries (unlike XFCE)
- Status: FAILS (no systemd in container)

### 3. MATE (tested, WORKS with DCV-GL on DCV 2025.0)

- GNOME 2 fork, does NOT require systemd
- `mate-session --disable-acceleration-check` starts standalone with just dbus
- Available in EPEL for Rocky 9
- DCV 2024.0: segfaults with DCV-GL (same as XFCE)
- DCV 2025.0: WORKS with DCV-GL enabled — no segfaults
- Full desktop: marco (WM), mate-panel, caja (file manager), mate-settings-daemon
- Needs pre-created `/run/user/1000` with correct ownership and `/tmp/.ICE-unix`
- Status: WORKING (gl on, DCV 2025.0)

### 4. Metacity + xterm (tested, works with DCV-GL)

- AWS docs recommend as "failsafe" virtual session
- Minimal: just a window manager + terminal
- DCV-GL works (no segfaults)
- Not a real desktop — no panel, no file manager, no app launcher
- Good for single-app kiosk mode (e.g., just Blender)
- Status: WORKING (gl on), but minimal UX

### 5. KDE Plasma (not tested)

- Needs SDDM display manager
- Heavy, complex setup
- Not officially supported on RHEL/Rocky (needs third-party repos)
- Overkill for container use case
- Status: SKIPPED

### 6. Cinnamon (not tested)

- GNOME 3 fork with traditional desktop layout
- Available in EPEL for Rocky 9
- May or may not need systemd (unclear)
- ni-sp.com documents it with GDM on Rocky 9 (implies systemd)
- Status: SKIPPED (likely same systemd issue as GNOME)

## Key Finding

DCV-GL (DCV's built-in GL interception) has issues in containers:
- DCV 2024.0: crashes all GTK3 desktops (XFCE, MATE) via LD_PRELOAD
- DCV 2025.0: no crashes, but DCV-GL can't find a GL vendor on Xdcv display — falls back to llvmpipe

VirtualGL is the solution for true GPU-accelerated OpenGL in containers:
- Desktop runs on software rendering (fine for panels/file manager)
- Individual apps get GPU acceleration via `vglrun <app>`
- `vglrun glxinfo` confirms NVIDIA GPU rendering
- Blender desktop shortcut uses `Exec=vglrun /opt/blender/blender`

The winning combination: MATE + DCV 2025.0 + VirtualGL + `--gl off` + `--device /dev/dri:/dev/dri`

## Test Plan (ordered by likelihood of success)

1. MATE with `--gl on` — best chance of full desktop + DCV-GL
2. Metacity fallback with `--gl on` — if MATE fails, use as kiosk mode

## References

- [ni-sp.com: KDE, GNOME, MATE and others with DCV](https://www.ni-sp.com/knowledge-base/dcv-general/kde-gnome-mate-and-others/)
- [ni-sp.com: DCV in Containers](https://www.ni-sp.com/knowledge-base/dcv-installation/linux-containers/)
- [AWS: Creating a Failsafe Virtual Session](https://docs.aws.amazon.com/dcv/latest/adminguide/creating-linux-failsafe-virtual-session-creation.html)
- [AWS: DCV Prerequisites for Linux](https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html)
