$ErrorActionPreference = 'Continue'
# Simulate a fresh C: drive (warm boot): remove everything the installer put on C:.
# The D: volume keeps the payload + graft artifacts.

Write-Host "=== Stop + delete services ==="
foreach ($s in 'Autodesk Access Service Host', 'AdskLicensingService', 'FlexNet Licensing Service 64') {
    Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    sc.exe delete "$s" | Out-Null
    Write-Host "deleted service: $s (rc=$LASTEXITCODE)"
}

Write-Host "=== Delete Autodesk registry subtrees ==="
foreach ($k in 'HKLM\SOFTWARE\Autodesk', 'HKLM\SOFTWARE\Wow6432Node\Autodesk') {
    reg.exe delete $k /f | Out-Null
    Write-Host "deleted: $k (rc=$LASTEXITCODE)"
}

Write-Host "=== Remove machine env var ==="
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_x64_2025', $null, 'Machine')

Write-Host "=== Remove junctions (link only, targets stay on D:) ==="
foreach ($link in 'C:\Program Files\Autodesk', 'C:\ProgramData\Autodesk',
                  'C:\Program Files\Common Files\Autodesk Shared',
                  'C:\Program Files (x86)\Common Files\Autodesk Shared') {
    if (Test-Path $link) { cmd /c rmdir "$link"; Write-Host "rmdir: $link (rc=$LASTEXITCODE)" }
}

Write-Host "=== Remove non-junctioned payloads on C: ==="
Remove-Item 'C:\Program Files\Common Files\Macrovision Shared' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\FLEXnet' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "=== Verify teardown ==="
Write-Host "Autodesk PF exists:   $(Test-Path 'C:\Program Files\Autodesk')"
Write-Host "Autodesk reg exists:  $(Test-Path 'HKLM:\SOFTWARE\Autodesk')"
Write-Host "AdskLicensing svc:    $((Get-Service AdskLicensingService -ErrorAction SilentlyContinue) -ne $null)"
Write-Host "Macrovision exists:   $(Test-Path 'C:\Program Files\Common Files\Macrovision Shared')"
Write-Host "D: payload intact:    $(Test-Path 'D:\Software\Autodesk\3ds Max 2025\3dsmaxbatch.exe')"
cmd /c exit 0
