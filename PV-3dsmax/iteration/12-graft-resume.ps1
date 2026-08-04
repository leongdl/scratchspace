$ErrorActionPreference = 'Stop'
$graft = 'D:\SoftwareRegistry\graft'

Write-Host "=== verify import took (spot checks) ==="
Write-Host "Autodesk key:  $(Test-Path 'HKLM:\SOFTWARE\Autodesk\3dsMax\27.0')"
Write-Host "3dsmax class:  $(Test-Path 'HKLM:\SOFTWARE\Classes\3dsmax')"

Write-Host "=== 4. Services via sc.exe create ==="
foreach ($file in Get-ChildItem "$graft\services\*.json") {
    $svc = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        $startType = switch ($svc.StartMode) { 'Auto' {'auto'} 'Manual' {'demand'} 'Disabled' {'disabled'} default {'auto'} }
        sc.exe create "$($svc.Name)" binPath= "$($svc.PathName)" start= $startType DisplayName= "$($svc.DisplayName)" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "sc create $($svc.Name) failed: $LASTEXITCODE" }
        Write-Host "created: $($svc.Name) [$startType]"
    } else { Write-Host "exists: $($svc.Name)" }
    if ($svc.Name -eq 'Autodesk Access Service Host') {
        sc.exe config "$($svc.Name)" start= disabled | Out-Null
        Write-Host "  -> Autodesk Access left disabled"
        continue
    }
    if ($svc.StartMode -eq 'Auto') {
        Start-Service -Name $svc.Name -ErrorAction Stop
        Write-Host "  -> started"
    }
}

Write-Host "=== 5. Machine env vars ==="
$maxRoot = 'C:\Program Files\Autodesk\3ds Max 2025'
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_x64_2025', "$maxRoot\", 'Machine')
[Environment]::SetEnvironmentVariable('3DSMAX_EXECUTABLE', "$maxRoot\3dsmaxbatch.exe", 'Machine')
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_BATCH_EXE', "$maxRoot\3dsmaxbatch.exe", 'Machine')
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_EXECUTABLE', "$maxRoot\3dsmax.exe", 'Machine')
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_LOCATION', $maxRoot, 'Machine')
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_VERSION', '2025', 'Machine')
$path = [Environment]::GetEnvironmentVariable('Path','Machine')
if ($path -notlike "*3ds Max 2025*") {
    [Environment]::SetEnvironmentVariable('Path', "$maxRoot;$maxRoot\Python;$maxRoot\Python\Scripts;$path", 'Machine')
}
Write-Host "env set"
Write-Host "=== services state ==="
Get-Service AdskLicensingService, 'FlexNet Licensing Service 64', 'Autodesk Access Service Host' -ErrorAction SilentlyContinue |
  Format-Table Name, Status, StartType -AutoSize | Out-String
