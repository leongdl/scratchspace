$ErrorActionPreference = 'Stop'
$snap = 'D:\SoftwareRegistry\snapshots'
$graft = 'D:\SoftwareRegistry\graft'
New-Item -ItemType Directory -Force -Path $graft, "$graft\services" | Out-Null

# --- 1. Filtered .reg from the AFTER export: everything the installer added,
#        minus Windows Installer bookkeeping noise. Plus the full Autodesk
#        subtrees (covers modified values too).
$afterReg = Get-ChildItem "$snap\after-*-HKLM-SOFTWARE.reg" | Sort-Object Name | Select-Object -Last 1
$added = [Collections.Generic.HashSet[string]]::new(
    [string[]](Get-Content "$snap\added-software-keys.txt"))
Write-Host "Added set: $($added.Count) keys; source: $($afterReg.Name)"

$keepPrefixes = @(
    '[HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk',
    '[HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Autodesk'
)
$dropPrefix = '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\'

$outPath = "$graft\autodesk-graft.reg"
$reader = [IO.StreamReader]::new($afterReg.FullName, $true)
$writer = [IO.StreamWriter]::new($outPath, $false, [Text.Encoding]::Unicode)
$writer.WriteLine('Windows Registry Editor Version 5.00')
$writer.WriteLine('')
$keep = $false
$kept = 0
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        if ($line.StartsWith('[HKEY')) {
            $keep = $false
            foreach ($p in $keepPrefixes) { if ($line.StartsWith($p)) { $keep = $true; break } }
            if (-not $keep -and $added.Contains($line) -and -not $line.StartsWith($dropPrefix)) { $keep = $true }
            if ($keep) { $kept++ }
        }
        if ($keep -and -not $line.StartsWith('Windows Registry Editor')) { $writer.WriteLine($line) }
    }
} finally { $reader.Dispose(); $writer.Dispose() }
Write-Host "Graft reg written: $kept keys -> $outPath ($([math]::Round((Get-Item $outPath).Length/1MB,1)) MB)"

# --- 2. Service registry keys + JSON definitions ---
$svcNames = @('AdskLicensingService', 'FlexNet Licensing Service 64', 'Autodesk Access Service Host')
foreach ($s in $svcNames) {
    $safe = $s -replace '[^A-Za-z0-9]', '_'
    reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$s" "$graft\services\svc-$safe.reg" /y | Out-Null
    Write-Host "Exported service key: $s (rc=$LASTEXITCODE)"
    $svc = Get-CimInstance Win32_Service -Filter "Name='$s'"
    if ($svc) {
        @{ Name=$svc.Name; DisplayName=$svc.DisplayName; PathName=$svc.PathName
           StartMode=$svc.StartMode; StartName=$svc.StartName; Description=$svc.Description
        } | ConvertTo-Json | Out-File "$graft\services\svc-$safe.json" -Encoding utf8
    }
}

# --- 3. Copy service/licensing payloads that live OUTSIDE the junction set ---
robocopy 'C:\Program Files\Common Files\Macrovision Shared' 'D:\Software\MacrovisionShared' /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy MacrovisionShared failed: $LASTEXITCODE" }
Write-Host "Copied Macrovision Shared (rc=$LASTEXITCODE)"
robocopy 'C:\ProgramData\FLEXnet' 'D:\SoftwareData\FLEXnet' /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy FLEXnet failed: $LASTEXITCODE" }
Write-Host "Copied FLEXnet ProgramData (rc=$LASTEXITCODE)"
cmd /c exit 0

# --- 4. Machine env graft ---
@{ 'ADSK_3DSMAX_x64_2025' = [Environment]::GetEnvironmentVariable('ADSK_3DSMAX_x64_2025','Machine') } |
    ConvertTo-Json | Out-File "$graft\machine-env.json" -Encoding utf8

# --- 5. Install-state marker ---
@{ schemaVersion = 1; maxVersion = '2025'
   maxInstallerUri = 's3://common-bealinerezpackage-resources-bucket/3dsmax/2025/3dsMax2025.zip'
   installedAt = (Get-Date -Format o) } |
    ConvertTo-Json | Out-File 'D:\.install-state.json' -Encoding utf8

Write-Host "=== graft dir ==="
Get-ChildItem $graft -Recurse | Format-Table FullName, @{n='KB';e={[math]::Round($_.Length/1KB)}} -AutoSize | Out-String
