$ErrorActionPreference = 'Continue'
Write-Host "=== Env contract (fresh process, Machine scope) ==="
foreach ($v in '3DSMAX_EXECUTABLE','ADSK_3DSMAX_BATCH_EXE','ADSK_3DSMAX_LOCATION','ADSK_3DSMAX_VERSION','DEADLINE_PERSISTENT_MOUNT') {
    Write-Host ("  {0} = {1}" -f $v, [Environment]::GetEnvironmentVariable($v,'Machine'))
}
$exe = [Environment]::GetEnvironmentVariable('3DSMAX_EXECUTABLE','Machine')
Write-Host "=== $exe -help (post-graft) ==="
$sw = [Diagnostics.Stopwatch]::StartNew()
$out = & $exe -help 2>&1 | Out-String
$sw.Stop()
Write-Host "exit code: $LASTEXITCODE  elapsed: $($sw.Elapsed.ToString('mm\:ss'))"
$clean = $out -replace '\x00',''
Write-Host $clean.Substring(0, [Math]::Min(300, $clean.Length))
Write-Host "=== 3dsmax.exe resolves through junction ==="
Test-Path ([Environment]::GetEnvironmentVariable('ADSK_3DSMAX_EXECUTABLE','Machine'))
Write-Host "=== AdskLicensing helper responds ==="
$lic = 'C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\helper\AdskLicensingInstHelper.exe'
if (Test-Path $lic) { & $lic list 2>&1 | Select-Object -First 12 | Out-String | Write-Host } else { Write-Host "helper not found: $lic" }
