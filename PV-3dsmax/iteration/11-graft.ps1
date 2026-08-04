$ErrorActionPreference = 'Stop'
$graft = 'D:\SoftwareRegistry\graft'
$total = [Diagnostics.Stopwatch]::StartNew()

Write-Host "=== 1. Junctions ==="
$junctions = @(
    @{ Link = 'C:\Program Files\Autodesk';                           Target = 'D:\Software\Autodesk' }
    @{ Link = 'C:\ProgramData\Autodesk';                             Target = 'D:\SoftwareData\Autodesk' }
    @{ Link = 'C:\Program Files\Common Files\Autodesk Shared';       Target = 'D:\Software\AutodeskShared' }
    @{ Link = 'C:\Program Files (x86)\Common Files\Autodesk Shared'; Target = 'D:\Software\AutodeskSharedX86' }
)
foreach ($j in $junctions) {
    if (-not (Test-Path $j.Link)) {
        New-Item -ItemType Junction -Path $j.Link -Target $j.Target | Out-Null
        Write-Host "junction: $($j.Link)"
    }
}

Write-Host "=== 2. Non-junctioned payload restore (FlexNet) ==="
robocopy 'D:\Software\MacrovisionShared' 'C:\Program Files\Common Files\Macrovision Shared' /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy restore Macrovision failed: $LASTEXITCODE" }
robocopy 'D:\SoftwareData\FLEXnet' 'C:\ProgramData\FLEXnet' /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy restore FLEXnet failed: $LASTEXITCODE" }
cmd /c exit 0
Write-Host "restored"

Write-Host "=== 3. Registry import ==="
$sw = [Diagnostics.Stopwatch]::StartNew()
reg.exe import "$graft\autodesk-graft.reg" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg import graft failed: $LASTEXITCODE" }
$sw.Stop()
Write-Host ("imported autodesk-graft.reg in {0:mm\:ss}" -f $sw.Elapsed)

Write-Host "=== 4. Services via sc.exe create (SCM registration, no reboot needed) ==="
foreach ($file in Get-ChildItem "$graft\services\*.json") {
    $svc = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        $startType = switch ($svc.StartMode) { 'Auto' {'auto'} 'Manual' {'demand'} 'Disabled' {'disabled'} default {'auto'} }
        sc.exe create "$($svc.Name)" binPath= "$($svc.PathName)" start= $startType DisplayName= "$($svc.DisplayName)" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "sc create $($svc.Name) failed: $LASTEXITCODE" }
        Write-Host "created: $($svc.Name) [$startType]"
    }
    # Policy: leave Autodesk Access disabled on render workers
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
[Environment]::SetEnvironmentVariable('ADSK_3DSMAX_x64_2025', 'C:\Program Files\Autodesk\3ds Max 2025\', 'Machine')
# PR #173 contract, applied per-boot:
$maxRoot = 'C:\Program Files\Autodesk\3ds Max 2025'
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

$total.Stop()
Write-Host ("=== GRAFT COMPLETE in {0:mm\:ss} ===" -f $total.Elapsed)
