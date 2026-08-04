$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path D:\SoftwareRegistry\snapshots | Out-Null
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\pv-tools\registry-snapshot.ps1 snapshot -Label before -OutDir D:\SoftwareRegistry\snapshots
exit $LASTEXITCODE
