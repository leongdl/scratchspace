$ErrorActionPreference = 'Stop'
# Fast BEFORE snapshot: native reg.exe export of full hives + service table dump.
# reg.exe exports HKLM\SOFTWARE (~100-200MB of .reg text) in well under a minute,
# vs 30+ min for a PowerShell per-key walk. Diffing two .reg exports offline
# gives the same added/removed/modified key information.
$dir = 'D:\SoftwareRegistry\snapshots'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$sw = [Diagnostics.Stopwatch]::StartNew()
reg.exe export HKLM\SOFTWARE "$dir\before-$stamp-HKLM-SOFTWARE.reg" /y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg export SOFTWARE failed" }
reg.exe export HKLM\SYSTEM\CurrentControlSet\Services "$dir\before-$stamp-Services.reg" /y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg export Services failed" }
$sw.Stop()

Get-CimInstance Win32_Service |
  Select-Object Name, DisplayName, PathName, StartMode, State, StartName |
  ConvertTo-Json -Depth 3 | Out-File "$dir\before-$stamp-services.json" -Encoding utf8

# Also capture the machine environment variables for the graft comparison.
[Environment]::GetEnvironmentVariables('Machine') | ConvertTo-Json | Out-File "$dir\before-$stamp-machine-env.json" -Encoding utf8

Write-Host ("Export took {0:mm\:ss}" -f $sw.Elapsed)
Get-ChildItem $dir | Format-Table Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} -AutoSize | Out-String
