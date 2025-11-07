1. KeenTools 2025.2.0
Type: Nuke Plugin (.so)

Main Plugin: /usr/local/NUKE/14.1/plugins/KeenTools/plugin_libs/KeenTools.so
Location: Nuke-specific plugin directory
Format: Native Nuke plugin (not OFX)
2. NeatVideo 6 OFX Demo
Type: OFX Plugin (.ofx)

Main Plugin: /usr/local/Neat Video v6 OFX/NeatVideo6.ofx.bundle/Contents/Linux-x86-64/NeatVideo6.ofx
Symlink: /usr/OFX/Plugins/NeatVideo6.ofx.bundle → /usr/local/Neat Video v6 OFX/NeatVideo6.ofx.bundle
Location: Standard OFX directory (via symlink)
3. RSMB 6 OFX (ReelSmart Motion Blur)
Type: OFX Plugins (.ofx) - 3 variants

Main RSMB: /usr/OFX/Plugins/RSMB6OFX/rsmb.ofx.bundle/Contents/Linux-x86-64/rsmb.ofx
Regular RSMB: /usr/OFX/Plugins/RSMB6OFX/rsmbregular.ofx.bundle/Contents/Linux-x86-64/rsmbregular.ofx
Vector RSMB: /usr/OFX/Plugins/RSMB6OFX/rsmbvectors.ofx.bundle/Contents/Linux-x86-64/rsmbvectors.ofx
Location: Standard OFX directory
Summary:
1 Nuke Plugin (.so): KeenTools
4 OFX Plugins (.ofx): 1 NeatVideo + 3 RSMB variants
All accessible to Nuke via standard plugin discovery paths
