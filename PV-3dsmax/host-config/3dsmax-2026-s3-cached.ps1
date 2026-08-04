<#
3ds Max 2026 host configuration with S3-FIRST caching for AWS Deadline Cloud Windows SMF.

Architecture (generation 2 - S3 is the primary tier, the persistent volume is an
optional accelerator):

  The cache root is the fleet's persistent volume when one is attached
  (DEADLINE_PERSISTENT_MOUNT), otherwise a local folder on C:. Everything below works
  identically either way, because the payload is always reached through NTFS junctions
  pointing at the cache root - the zip layout is the same regardless of where it lives.

  S3-COLD    no S3 zip anywhere  -> claim token, real installer through junctions,
             capture registry/services/licensing, zip the cache root payload, publish
             to S3, release token. Happens ONCE per version, farm-wide.
  S3-WARM    S3 zip exists       -> download + extract into the cache root (any AZ,
             any fleet, PV or not), then graft. Minutes instead of a 15-25 min install.
  PV-WARM    (add-on) cache root is a persistent volume that already holds a valid
             payload from a previous boot -> skip the download entirely, graft in
             seconds.
  WAIT       another worker holds the install token -> poll for its zip; stale token
             (crashed installer) is taken over.

Zip contents: Software\ SoftwareData\ SoftwareRegistry\ .install-state.json - i.e. the
junction-target files, the registry .reg captures, service JSON, licensing payloads
(FlexNet), and the state marker.

Deployed via bootstrap-host-config (S3 fetch) - no 15,000-char scriptBody limit.
Fleet role needs R/W on <bucket>/DeadlineCloud/pv-cache/* (policy in artifacts/README.md).

Lessons already baked in (see JOURNAL.md traps T1-T10 + tar fix 2026-08-04):
stderr containment for reg.exe/pip/tar/aws, sc.exe for SCM-visible services, forward
slashes for tar -C, services stopped around archiving, conditional-write token.
#>

$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
$MAX_VERSION = "2026"
$3DS_MAX_INSTALLER_ZIP_S3_URI = "s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2026/installers/3dsMax2026.zip"
$S3_CACHE = "s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2026"
$LOCAL_CACHE_ROOT = "C:\DeadlineCache"   # used when the fleet has no persistent volume
$FORCE_REINSTALL = $false
$TOKEN_STALE_MIN = 75
$WAIT_ZIP_MAX_MIN = 40
# END CONFIG ============

$ZIP_URI = "$S3_CACHE/pv-payload.zip"
$TOKEN_URI = "$S3_CACHE/installing.token"
$MAX_ROOT = "C:\Program Files\Autodesk\3ds Max $MAX_VERSION"

function Write-Duration($start, $name) { Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }

function Invoke-Native([string]$line, [string]$errCtx) {
    cmd /c "$line >nul 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "$errCtx failed: $LASTEXITCODE" }
}
function Invoke-Tar([string]$argLine, [string]$errCtx) {
    $errFile = "$env:TEMP\tar-err.txt"
    cmd /c "tar.exe $argLine 2>`"$errFile`""
    if ($LASTEXITCODE -ne 0) {
        $err = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' '
        throw "$errCtx failed ($LASTEXITCODE): $err"
    }
}
function Invoke-Robocopy([string]$src, [string]$dst) {
    robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy '$src' -> '$dst' failed: $LASTEXITCODE" }
    cmd /c exit 0
}

function Split-S3Uri([string]$uri) {
    if ($uri -notmatch '^s3://([^/]+)/(.+)$') { throw "bad s3 uri: $uri" }
    return @{ Bucket = $Matches[1]; Key = $Matches[2] }
}
function Test-S3Object([string]$uri) {
    $p = Split-S3Uri $uri
    cmd /c "aws s3api head-object --bucket `"$($p.Bucket)`" --key `"$($p.Key)`" >nul 2>&1"
    return ($LASTEXITCODE -eq 0)
}
function Get-S3ObjectAgeMinutes([string]$uri) {
    $p = Split-S3Uri $uri
    $out = cmd /c "aws s3api head-object --bucket `"$($p.Bucket)`" --key `"$($p.Key)`" --query LastModified --output text 2>nul"
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return [int]((Get-Date).ToUniversalTime() - [DateTime]::Parse($out).ToUniversalTime()).TotalMinutes
}

function Get-InstallClaim {
    $p = Split-S3Uri $TOKEN_URI
    $tmp = "$env:TEMP\pv-token.txt"
    "$((Get-Date).ToUniversalTime().ToString('o')) $env:COMPUTERNAME" | Out-File $tmp -Encoding ascii
    cmd /c "aws s3api put-object --bucket `"$($p.Bucket)`" --key `"$($p.Key)`" --body `"$tmp`" --if-none-match `"*`" >nul 2>`"$env:TEMP\pv-token-err.txt`""
    if ($LASTEXITCODE -eq 0) { Write-Host "install token claimed (conditional)"; return $true }
    $err = Get-Content "$env:TEMP\pv-token-err.txt" -Raw -ErrorAction SilentlyContinue
    if ($err -match 'PreconditionFailed|412') {
        Write-Host "token already held"
    } elseif ($err -match 'Unknown options|if-none-match') {
        if (-not (Test-S3Object $TOKEN_URI)) {
            cmd /c "aws s3 cp `"$tmp`" `"$TOKEN_URI`" >nul 2>&1"
            if ($LASTEXITCODE -eq 0) { Write-Host "install token claimed (racy fallback)"; return $true }
        }
        Write-Host "token already held (racy check)"
    } else {
        Write-Host "token claim error (treating as held)"
    }
    $age = Get-S3ObjectAgeMinutes $TOKEN_URI
    if ($null -ne $age -and $age -gt $TOKEN_STALE_MIN -and -not (Test-S3Object $ZIP_URI)) {
        Write-Host "token stale (${age}m > ${TOKEN_STALE_MIN}m, no zip) - taking over"
        cmd /c "aws s3 cp `"$tmp`" `"$TOKEN_URI`" >nul 2>&1"
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}
function Remove-InstallToken { cmd /c "aws s3 rm `"$TOKEN_URI`" >nul 2>&1"; cmd /c exit 0 }

# --- Cache root: PV when available, local disk otherwise ----------------------
$MOUNT = [Environment]::GetEnvironmentVariable("DEADLINE_PERSISTENT_MOUNT", "Machine")
$HAS_PV = -not [string]::IsNullOrEmpty($MOUNT)
$CACHE_ROOT = if ($HAS_PV) { $MOUNT } else { $LOCAL_CACHE_ROOT }
if (-not $HAS_PV) { New-Item -ItemType Directory -Force -Path $CACHE_ROOT | Out-Null }
Write-Host "Cache root: $CACHE_ROOT (persistent volume: $HAS_PV)"
$SW = "$CACHE_ROOT\Software"; $DATA = "$CACHE_ROOT\SoftwareData"
$GRAFT = "$CACHE_ROOT\SoftwareRegistry\graft"; $STATE = "$CACHE_ROOT\.install-state.json"

$junctions = @(
    @{ Link = "C:\Program Files\Autodesk";                           Target = "$SW\Autodesk" }
    @{ Link = "C:\ProgramData\Autodesk";                             Target = "$DATA\Autodesk" }
    @{ Link = "C:\Program Files\Common Files\Autodesk Shared";       Target = "$SW\AutodeskShared" }
    @{ Link = "C:\Program Files (x86)\Common Files\Autodesk Shared"; Target = "$SW\AutodeskSharedX86" }
)
function Initialize-Junctions([bool]$CreateTargets) {
    foreach ($j in $junctions) {
        if (Test-Path $j.Link) {
            $item = Get-Item $j.Link -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            Remove-Item $j.Link -Recurse -Force
        }
        $parent = Split-Path $j.Link -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        if ($CreateTargets) { New-Item -ItemType Directory -Path $j.Target -Force | Out-Null }
        New-Item -ItemType Junction -Path $j.Link -Target $j.Target | Out-Null
        Write-Host "Junction: $($j.Link) -> $($j.Target)"
    }
}

function Set-EnvContract {
    [Environment]::SetEnvironmentVariable("3DSMAX_EXECUTABLE",      "$MAX_ROOT\3dsmaxbatch.exe", "Machine")
    [Environment]::SetEnvironmentVariable("ADSK_3DSMAX_BATCH_EXE",  "$MAX_ROOT\3dsmaxbatch.exe", "Machine")
    [Environment]::SetEnvironmentVariable("ADSK_3DSMAX_EXECUTABLE", "$MAX_ROOT\3dsmax.exe",      "Machine")
    [Environment]::SetEnvironmentVariable("ADSK_3DSMAX_LOCATION",   $MAX_ROOT,                   "Machine")
    [Environment]::SetEnvironmentVariable("ADSK_3DSMAX_VERSION",    $MAX_VERSION,                "Machine")
    [Environment]::SetEnvironmentVariable("ADSK_3DSMAX_x64_$MAX_VERSION", "$MAX_ROOT\",          "Machine")
    [Environment]::SetEnvironmentVariable("PYTHONPATH", "$MAX_ROOT\Python;$MAX_ROOT\Python\Scripts", "Machine")
    $path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($path -notlike "*3ds Max $MAX_VERSION*") {
        [Environment]::SetEnvironmentVariable("Path", "$MAX_ROOT;$MAX_ROOT\Python;$MAX_ROOT\Python\Scripts;$path", "Machine")
    }
}

$ServiceNames = @("AdskLicensingService", "FlexNet Licensing Service 64", "Autodesk Access Service Host")

function Export-InstallerState {
    New-Item -ItemType Directory -Force -Path "$GRAFT\services" | Out-Null
    foreach ($s in $ServiceNames) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$s'"
        if ($svc) {
            @{ Name=$svc.Name; DisplayName=$svc.DisplayName; PathName=$svc.PathName
               StartMode=$svc.StartMode; StartName=$svc.StartName; Description=$svc.Description
            } | ConvertTo-Json | Out-File "$GRAFT\services\$($s -replace '[^A-Za-z0-9]','_').json" -Encoding utf8
            Write-Host "Captured service: $s"
        }
    }
    Invoke-Robocopy "C:\Program Files\Common Files\Macrovision Shared" "$SW\MacrovisionShared"
    Invoke-Robocopy "C:\ProgramData\FLEXnet" "$DATA\FLEXnet"
    # 3ds Max 2026 requires the .NET (Core) Desktop Runtime, which ODIS installs to
    # C:\Program Files\dotnet - OUTSIDE the junction set. Without this capture, an
    # S3-restored worker dies with "Terminating due to required .NET Core version not
    # present" on full Max init (found live 2026-08-04; -help does NOT catch it).
    if (Test-Path "C:\Program Files\dotnet") {
        Invoke-Robocopy "C:\Program Files\dotnet" "$SW\dotnet"
        cmd /c "reg.exe export `"HKLM\SOFTWARE\dotnet`" `"$GRAFT\hklm-dotnet.reg`" /y >nul 2>&1"
        cmd /c "reg.exe export `"HKLM\SOFTWARE\Wow6432Node\dotnet`" `"$GRAFT\hklm-wow-dotnet.reg`" /y >nul 2>&1"
        cmd /c exit 0
        Write-Host "Captured .NET Core runtime payload + registry"
    }
    Invoke-Native "reg.exe export `"HKLM\SOFTWARE\Autodesk`" `"$GRAFT\hklm-autodesk.reg`" /y" "reg export Autodesk"
    Invoke-Native "reg.exe export `"HKLM\SOFTWARE\Wow6432Node\Autodesk`" `"$GRAFT\hklm-wow-autodesk.reg`" /y" "reg export WOW Autodesk"
    foreach ($cls in "3dsmax","3dschr","3dsifl","3dsms","3dsmxp","3dsmcr",".max") {
        cmd /c "reg.exe export `"HKLM\SOFTWARE\Classes\$cls`" `"$GRAFT\cls-$($cls -replace '\.','_').reg`" /y >nul 2>&1"
    }
    cmd /c exit 0
    Write-Host "Registry graft exported"
}

function Import-InstallerState {
    Invoke-Robocopy "$SW\MacrovisionShared" "C:\Program Files\Common Files\Macrovision Shared"
    Invoke-Robocopy "$DATA\FLEXnet" "C:\ProgramData\FLEXnet"
    if (Test-Path "$SW\dotnet") {
        Invoke-Robocopy "$SW\dotnet" "C:\Program Files\dotnet"
        Write-Host "Restored .NET Core runtime"
    }
    foreach ($regFile in Get-ChildItem "$GRAFT\*.reg") {
        Invoke-Native "reg.exe import `"$($regFile.FullName)`"" "reg import $($regFile.Name)"
        Write-Host "Imported $($regFile.Name)"
    }
    foreach ($file in Get-ChildItem "$GRAFT\services\*.json") {
        $svc = Get-Content $file.FullName -Raw | ConvertFrom-Json
        if (-not (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue)) {
            $startType = switch ($svc.StartMode) { "Auto" {"auto"} "Manual" {"demand"} "Disabled" {"disabled"} default {"auto"} }
            sc.exe create "$($svc.Name)" binPath= "$($svc.PathName)" start= $startType DisplayName= "$($svc.DisplayName)" | Out-Null
            Write-Host "Registered service: $($svc.Name)"
        }
        if ($svc.Name -eq "Autodesk Access Service Host") {
            sc.exe config "$($svc.Name)" start= disabled | Out-Null; continue
        }
        if ($svc.StartMode -eq "Auto") {
            try { Start-Service -Name $svc.Name } catch { Write-Host "WARNING: could not start $($svc.Name): $_" }
        }
    }
}

function Test-StateValid {
    if ($FORCE_REINSTALL) { return $false }
    if (-not (Test-Path $STATE)) { return $false }
    try { $s = Get-Content $STATE -Raw | ConvertFrom-Json } catch { return $false }
    $want = Split-Path $3DS_MAX_INSTALLER_ZIP_S3_URI -Leaf
    $have = Split-Path ([string]$s.maxInstallerUri) -Leaf
    return ($s.maxVersion -eq $MAX_VERSION -and $have -eq $want)
}
function Write-StateFile {
    @{ schemaVersion = 1; maxVersion = $MAX_VERSION
       maxInstallerUri = $3DS_MAX_INSTALLER_ZIP_S3_URI
       installedAt = (Get-Date -Format o) } | ConvertTo-Json | Out-File $STATE -Encoding utf8
}

function Install-3dsMax {
    $dl = Get-Date
    $setupDir = "$CACHE_ROOT\installers"
    New-Item -ItemType Directory -Force -Path $setupDir | Out-Null
    if (-not (Test-Path "$setupDir\3dsmax.zip")) {
        Invoke-Native "aws s3 cp --no-progress `"$3DS_MAX_INSTALLER_ZIP_S3_URI`" `"$setupDir\3dsmax.zip`"" "installer download"
    }
    Write-Duration $dl "Download"
    $ex = Get-Date
    if (-not (Test-Path "$setupDir\extracted")) {
        Expand-Archive "$setupDir\3dsmax.zip" "$setupDir\extracted" -Force
    }
    Write-Duration $ex "Extract"
    $setup = Get-ChildItem -Path "$setupDir\extracted" -Filter "Setup.exe" -Recurse | Select-Object -First 1
    if (-not $setup) { throw "Setup.exe not found in installer archive" }
    $inst = Get-Date
    $p = Start-Process -FilePath $setup.FullName -ArgumentList "-q" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Setup.exe failed: $($p.ExitCode)" }
    Write-Duration $inst "Install"
    if (-not (Test-Path "$MAX_ROOT\3dsmaxbatch.exe")) { throw "3dsmaxbatch.exe missing after install" }
}

function Install-Adaptor {
    $py = "$MAX_ROOT\Python\python.exe"
    cmd /c "`"$py`" -m ensurepip >nul 2>&1"
    cmd /c "`"$py`" -m pip install --upgrade --quiet deadline-cloud-for-3ds-max >nul 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "adaptor pip install failed: $LASTEXITCODE" }
    if (-not (Test-Path "$MAX_ROOT\Python\Scripts\3dsmax-openjd.exe")) { throw "3dsmax-openjd.exe missing after pip install" }
    Write-Host "adaptor installed (3dsmax-openjd present)"
}

function Test-Render {
    $out = & "$MAX_ROOT\3dsmaxbatch.exe" -help 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "3dsmaxbatch -help failed: $LASTEXITCODE" }
    # -help does NOT exercise full Max init. 3ds Max 2026 hard-requires the .NET
    # Desktop Runtime ("Terminating due to required .NET Core version not present",
    # exit -11, found live on an S3-restored worker). Verify it explicitly.
    $dotnet = "C:\Program Files\dotnet\dotnet.exe"
    if (-not (Test-Path $dotnet)) { throw ".NET runtime missing (C:\Program Files\dotnet)" }
    $runtimes = & $dotnet --list-runtimes 2>&1 | Out-String
    if ($runtimes -notmatch 'Microsoft\.WindowsDesktop\.App') { throw ".NET Desktop Runtime not registered" }
    Write-Host "3dsmaxbatch responds OK; .NET Desktop Runtime present"
}

function Publish-S3Zip {
    $zipLocal = "$CACHE_ROOT\pv-payload.zip"
    if (Test-Path $zipLocal) { Remove-Item $zipLocal -Force }
    $running = @()
    foreach ($s in $ServiceNames) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { $running += $s; Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    }
    try {
        $t = Get-Date
        $rootFwd = $CACHE_ROOT.TrimEnd('\') + '/'
        Invoke-Tar "-a -cf `"$zipLocal`" -C `"$rootFwd`" Software SoftwareData SoftwareRegistry .install-state.json" "tar create"
        Write-Duration $t "Zip create ($([math]::Round((Get-Item $zipLocal).Length/1GB,1)) GB)"
    } finally {
        foreach ($s in $running) { try { Start-Service -Name $s } catch { Write-Host "WARNING: restart $s failed: $_" } }
    }
    $t = Get-Date
    Invoke-Native "aws s3 cp --no-progress `"$zipLocal`" `"$ZIP_URI`"" "zip upload"
    Write-Duration $t "Zip upload"
    Remove-Item $zipLocal -Force
}
function Restore-S3Zip {
    $zipLocal = "$CACHE_ROOT\pv-payload.zip"
    $t = Get-Date
    Invoke-Native "aws s3 cp --no-progress `"$ZIP_URI`" `"$zipLocal`"" "zip download"
    Write-Duration $t "Zip download"
    $t = Get-Date
    $rootFwd = $CACHE_ROOT.TrimEnd('\') + '/'
    Invoke-Tar "-xf `"$zipLocal`" -C `"$rootFwd`"" "tar extract"
    Write-Duration $t "Zip extract"
    Remove-Item $zipLocal -Force
}

function Invoke-Graft {
    Initialize-Junctions -CreateTargets $false
    Import-InstallerState
    Set-EnvContract
    Install-Adaptor
    Test-Render
}

# === MAIN =====================================================================
$t0 = Get-Date

# PV-WARM (the persistent-volume add-on): only possible when the cache root survives
# reboots. Without a PV the local cache root is empty on every fresh worker.
if ($HAS_PV -and (Test-StateValid)) {
    Write-Host "=== PV-WARM boot: grafting cached install ==="
    try {
        Invoke-Graft
        Write-Duration $t0 "Total (PV-warm graft)"
        if (-not (Test-S3Object $ZIP_URI)) {
            if (Get-InstallClaim) {
                Write-Host "=== Seeding S3 zip from this volume (one-time) ==="
                try { Publish-S3Zip } catch { Write-Host "WARNING: S3 seed failed (non-fatal): $_" }
                Remove-InstallToken
            }
        }
        exit 0
    } catch {
        Write-Host "WARNING: graft failed ($_). Invalidating cache."
        Remove-Item $STATE -Force -ErrorAction SilentlyContinue
    }
}

# S3-WARM (primary tier): restore the payload from the farm-global zip.
if (Test-S3Object $ZIP_URI) {
    Write-Host "=== S3-WARM boot: restoring cache root from S3 zip ==="
    try {
        Restore-S3Zip
        if (-not (Test-StateValid)) { throw "state file invalid after zip restore" }
        Invoke-Graft
        Write-Duration $t0 "Total (S3-warm restore + graft)"
        exit 0
    } catch {
        Write-Host "WARNING: S3 restore failed ($_). Falling through to cold install."
        Remove-Item $STATE -Force -ErrorAction SilentlyContinue
    }
}

# S3-COLD (token-guarded, once per version farm-wide) or WAIT.
$claimed = Get-InstallClaim
if (-not $claimed) {
    Write-Host "=== WAIT: another worker is installing; polling for S3 zip ==="
    $deadline = (Get-Date).AddMinutes($WAIT_ZIP_MAX_MIN)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 60
        if (Test-S3Object $ZIP_URI) {
            Write-Host "zip appeared - taking S3-WARM path"
            Restore-S3Zip
            if (Test-StateValid) { Invoke-Graft; Write-Duration $t0 "Total (waited + S3-warm)"; exit 0 }
            break
        }
        if (Get-InstallClaim) { $claimed = $true; break }
    }
    if (-not $claimed) { throw "timed out waiting for concurrent install to publish the S3 zip" }
}

Write-Host "=== S3-COLD boot: installing and publishing the farm-global zip ==="
try {
    Initialize-Junctions -CreateTargets $true
    Install-3dsMax
    Export-InstallerState
    Set-EnvContract
    Install-Adaptor
    Write-StateFile
    Test-Render
    Write-Host "=== Publishing S3 zip ==="
    try { Publish-S3Zip } catch { Write-Host "WARNING: S3 publish failed (non-fatal): $_" }
} finally {
    Remove-InstallToken
}
Write-Duration $t0 "Total (cold install + capture + publish)"
exit 0
