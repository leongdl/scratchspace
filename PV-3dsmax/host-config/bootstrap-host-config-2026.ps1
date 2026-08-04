<#
Bootstrap host configuration (3ds Max 2026 variant): downloads the real script from S3.
Fleet role needs s3:GetObject on the script object.
#>
$ErrorActionPreference = "Stop"
trap { Write-Output "BOOTSTRAP ERROR: $($_.Exception.Message)"; exit 1 }

$SCRIPT_S3_URI = "s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2026/host-config.ps1"
$dst = "C:\ProgramData\Amazon\Deadline\pv-hostconfig.ps1"

New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
cmd /c "aws s3 cp --no-progress `"$SCRIPT_S3_URI`" `"$dst`" >nul 2>&1"
if ($LASTEXITCODE -ne 0) { throw "bootstrap download failed: $SCRIPT_S3_URI" }
Write-Host "Bootstrap: fetched $SCRIPT_S3_URI"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dst
exit $LASTEXITCODE
