$ErrorActionPreference = 'Continue'
Write-Host "=== 3dsmaxbatch.exe -help (baseline, cold install state) ==="
$exe = 'C:\Program Files\Autodesk\3ds Max 2025\3dsmaxbatch.exe'
$out = & $exe -help 2>&1 | Out-String
Write-Host "exit code: $LASTEXITCODE"
Write-Host $out.Substring(0, [Math]::Min(600, $out.Length))
Write-Host "=== check FLEXnet trusted storage / ProgramData dirs on C: ==="
foreach ($p in 'C:\ProgramData\FLEXnet', 'C:\Program Files\Common Files\Macrovision Shared') {
    Write-Host "$p exists: $(Test-Path $p)"
}
Write-Host "=== services state ==="
Get-Service AdskLicensingService, 'FlexNet Licensing Service 64' -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType -AutoSize | Out-String
