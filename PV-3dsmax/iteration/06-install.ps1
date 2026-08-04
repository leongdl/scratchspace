$ErrorActionPreference = 'Stop'
$setup = 'D:\installers\3dsmax2025\3dsMax2025\Setup.exe'
Write-Host "Starting silent install: $setup -q"
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $setup -ArgumentList '-q' -Wait -PassThru
$sw.Stop()
Write-Host ("Setup.exe exit code: {0}  elapsed: {1:hh\:mm\:ss}" -f $p.ExitCode, $sw.Elapsed)

Write-Host "=== C:\Program Files\Autodesk (through junction) ==="
Get-ChildItem 'C:\Program Files\Autodesk' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Write-Host "=== D:\Software\Autodesk (volume target) ==="
Get-ChildItem 'D:\Software\Autodesk' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Write-Host "=== 3dsmaxbatch.exe present? ==="
Test-Path 'C:\Program Files\Autodesk\3ds Max 2025\3dsmaxbatch.exe'
Write-Host "=== D: usage ==="
Get-PSDrive D | Select-Object @{n='UsedGB';e={[math]::Round($_.Used/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}} | Format-Table -AutoSize | Out-String
Write-Host "=== ODIS install log tail ==="
$log = Get-ChildItem "$env:ProgramData\Autodesk\ODIS\logs" -Filter *.log -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($log) { Write-Host $log.FullName; Get-Content $log.FullName -Tail 15 }
exit $p.ExitCode
