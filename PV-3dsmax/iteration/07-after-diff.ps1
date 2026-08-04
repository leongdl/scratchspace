$ErrorActionPreference = 'Stop'
$dir = 'D:\SoftwareRegistry\snapshots'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- AFTER export ---
$sw = [Diagnostics.Stopwatch]::StartNew()
reg.exe export HKLM\SOFTWARE "$dir\after-$stamp-HKLM-SOFTWARE.reg" /y | Out-Null
reg.exe export HKLM\SYSTEM\CurrentControlSet\Services "$dir\after-$stamp-Services.reg" /y | Out-Null
$sw.Stop()
Write-Host ("After export took {0:mm\:ss}" -f $sw.Elapsed)
Get-CimInstance Win32_Service | Select-Object Name, DisplayName, PathName, StartMode, State, StartName |
  ConvertTo-Json -Depth 3 | Out-File "$dir\after-$stamp-services.json" -Encoding utf8
[Environment]::GetEnvironmentVariables('Machine') | ConvertTo-Json | Out-File "$dir\after-$stamp-machine-env.json" -Encoding utf8

# --- Registry key diff (streaming, key paths only) ---
function Get-KeySet($file) {
    $set = [Collections.Generic.HashSet[string]]::new()
    $r = [IO.StreamReader]::new($file, $true)
    try {
        while ($null -ne ($line = $r.ReadLine())) {
            if ($line.StartsWith('[HKEY')) { [void]$set.Add($line) }
        }
    } finally { $r.Dispose() }
    return $set
}
$beforeSW = Get-ChildItem "$dir\before-*-HKLM-SOFTWARE.reg" | Sort-Object Name | Select-Object -First 1
$beforeSVC = Get-ChildItem "$dir\before-*-Services.reg" | Sort-Object Name | Select-Object -First 1
Write-Host "Diffing against: $($beforeSW.Name), $($beforeSVC.Name)"

$sw.Restart()
$b = Get-KeySet $beforeSW.FullName
$a = Get-KeySet "$dir\after-$stamp-HKLM-SOFTWARE.reg"
$bs = Get-KeySet $beforeSVC.FullName
$as2 = Get-KeySet "$dir\after-$stamp-Services.reg"
$sw.Stop()
Write-Host ("Key sets loaded in {0:mm\:ss}: SW before={1} after={2}; SVC before={3} after={4}" -f $sw.Elapsed, $b.Count, $a.Count, $bs.Count, $as2.Count)

$addedSW = [Collections.Generic.List[string]]::new()
foreach ($k in $a) { if (-not $b.Contains($k)) { $addedSW.Add($k) } }
$addedSVC = [Collections.Generic.List[string]]::new()
foreach ($k in $as2) { if (-not $bs.Contains($k)) { $addedSVC.Add($k) } }

$addedSW | Sort-Object | Out-File "$dir\added-software-keys.txt" -Encoding utf8
$addedSVC | Sort-Object | Out-File "$dir\added-service-keys.txt" -Encoding utf8

Write-Host "=== ADDED HKLM\SOFTWARE keys: $($addedSW.Count) — grouped by depth-3 prefix (top 40) ==="
$addedSW | Group-Object { ($_ -split '\\')[0..([Math]::Min(3, ($_ -split '\\').Count-1))] -join '\' } |
  Sort-Object Count -Descending | Select-Object -First 40 |
  ForEach-Object { Write-Host ("  [{0,6}] {1}" -f $_.Count, $_.Name) }

Write-Host "=== ADDED Services keys (top-level service names) ==="
$addedSVC | ForEach-Object { ($_ -split '\\')[4] } | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }

Write-Host "=== New Win32 services vs before ==="
$beforeSvcJson = (Get-Content (Get-ChildItem "$dir\before-*-services.json" | Select-Object -First 1).FullName -Raw | ConvertFrom-Json).Name
Get-CimInstance Win32_Service | Where-Object { $beforeSvcJson -notcontains $_.Name } |
  ForEach-Object { Write-Host "  $($_.Name) [$($_.StartMode)/$($_.State)] -> $($_.PathName)" }

Write-Host "=== New/changed Machine env vars ==="
$beforeEnv = Get-Content (Get-ChildItem "$dir\before-*-machine-env.json" | Select-Object -First 1).FullName -Raw | ConvertFrom-Json
$nowEnv = [Environment]::GetEnvironmentVariables('Machine')
foreach ($k in $nowEnv.Keys) {
    $old = $beforeEnv.PSObject.Properties[$k]
    if (-not $old) { Write-Host "  NEW: $k = $($nowEnv[$k])" }
    elseif ($old.Value -ne $nowEnv[$k]) { Write-Host "  CHANGED: $k" }
}
