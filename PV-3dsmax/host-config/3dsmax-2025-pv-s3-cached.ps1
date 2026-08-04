<#
3ds Max 2025 host configuration with TWO cache tiers for AWS Deadline Cloud Windows SMF:

  Tier 1 - Persistent volume (EBS, per fleet+AZ):  warm graft in seconds.
  Tier 2 - S3 payload zip (global):                seed any empty volume in minutes,
                                                   regardless of AZ. Solves the per-AZ
                                                   volume-pool fragmentation (trap T5).

Boot ladder:
  PV-WARM   volume has payload + valid state file -> junctions + registry/service graft.
            Opportunistically seeds the S3 zip if it doesn't exist yet (token-guarded).
  S3-WARM   volume invalid but S3 zip exists      -> download zip, extract to volume,
            then the same graft as PV-WARM.
  COLD      neither                                -> claim the install token, run the
            real installer through junctions, capture registry/services/licensing,
            zip {Software, SoftwareData, SoftwareRegistry, .install-state.json} and
            upload to S3, release token.
  WAIT      someone else holds the token           -> poll for the zip; if the token
            goes stale (crashed installer), take over and go COLD.

Concurrency token: 1-object claim at $TOKEN_URI containing "<timestamp> <worker>".
Claimed atomically with S3 conditional write (put-object --if-none-match '*'); if the
CLI predates conditional writes we fall back to racy check-then-put (worst case: two
workers both install; the second upload simply overwrites the first - idempotent).
A token older than $TOKEN_STALE_MIN minutes with no zip present is treated as a crashed
installer and taken over.

This script is deployed via a small bootstrap host config (bootstrap-host-config.ps1)
that downloads it from S3 - the inline hostConfiguration.scriptBody limit is 15,000
chars, and with the S3 tier the fleet role needs S3 access anyway.

Fleet requirements:
  - persistentVolumeConfiguration { mountPath: "D:", sizeGiB >= 100 } (tested at 500)
  - Fleet role: s3:GetObject/PutObject/DeleteObject on <bucket>/DeadlineCloud/pv-cache/*
    and scoped s3:ListBucket (see artifacts/README.md for the exact policy)
  - Host config timeout 3600s (worst path: WAIT poll + S3-WARM, or COLD + zip + upload)

Proven timings (2026-08-04, m5-class, 500 GiB gp3 @250 MiB/s):
  PV-WARM graft 4 s | installer download 1:32 | ODIS install 10:42-14:36 | full cold 13-20 min
#>

$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
$MAX_VERSION = "2025"
# Installer zip (see S3-INSTALLERS.md for how to stage it; fleet role must be able to read it)
$3DS_MAX_INSTALLER_ZIP_S3_URI = "s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2025/installers/3dsMax2025.zip"
# S3 cache tier location (fleet role needs RW here)
$S3_CACHE = "s3://leongdldevbucket/DeadlineCloud/pv-cache/3dsmax-2025"
$FORCE_REINSTALL = $false
$TOKEN_STALE_MIN = 75      # installer crash takeover threshold
$WAIT_ZIP_MAX_MIN = 40     # how long a non-installing worker waits for the zip
# END CONFIG ============

$ZIP_URI = "$S3_CACHE/pv-payload.zip"
$TOKEN_URI = "$S3_CACHE/installing.token"
$MAX_ROOT = "C:\Program Files\Autodesk\3ds Max $MAX_VERSION"

function Write-Duration($start, $name) { Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }

# T1: reg.exe/pip/tar/aws write benign output to stderr; strict mode turns that into
# fake failures. Every native call goes through cmd with streams contained.
function Invoke-Native([string]$line, [string]$errCtx) {
    cmd /c "$line >nul 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "$errCtx failed: $LASTEXITCODE" }
}

function Invoke-Robocopy([string]$src, [string]$dst) {
    robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy '$src' -> '$dst' failed: $LASTEXITCODE" }
    cmd /c exit 0
}

# --- S3 helpers (bucket/key split for s3api calls) ---------------------------
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

# --- Install token: returns $true when this worker should run the install ----
function Get-InstallClaim {
    $p = Split-S3Uri $TOKEN_URI
    $tmp = "$env:TEMP\pv-token.txt"
    "$((Get-Date).ToUniversalTime().ToString('o')) $env:COMPUTERNAME" | Out-File $tmp -Encoding ascii
    # Atomic claim via conditional write (S3 If-None-Match, CLI >= late-2024).
    cmd /c "aws s3api put-object --bucket `"$($p.Bucket)`" --key `"$($p.Key)`" --body `"$tmp`" --if-none-match `"*`" >nul 2>`"$env:TEMP\pv-token-err.txt`""
    if ($LASTEXITCODE -eq 0) { Write-Host "install token claimed (conditional)"; return $true }
    $err = Get-Content "$env:TEMP\pv-token-err.txt" -Raw -ErrorAction SilentlyContinue
    if ($err -match 'PreconditionFailed|412') {
        Write-Host "token already held"
    } elseif ($err -match 'Unknown options|if-none-match') {
        # Old CLI: racy fallback. Acceptable - duplicate installs converge on upload.
        if (-not (Test-S3Object $TOKEN_URI)) {
            cmd /c "aws s3 cp `"$tmp`" `"$TOKEN_URI`" >nul 2>&1"
            if ($LASTEXITCODE -eq 0) { Write-Host "install token claimed (racy fallback)"; return $true }
        }
        Write-Host "token already held (racy check)"
    } else {
        Write-Host "token claim error (treating as held): $($err -replace '\s+',' ' | Out-String)"
    }
    # Held by someone else - is it stale (crashed installer) with no zip to show for it?
    $age = Get-S3ObjectAgeMinutes $TOKEN_URI
    if ($null -ne $age -and $age -gt $TOKEN_STALE_MIN -and -not (Test-S3Object $ZIP_URI)) {
        Write-Host "token stale (${age}m > ${TOKEN_STALE_MIN}m, no zip) - taking over"
        cmd /c "aws s3 cp `"$tmp`" `"$TOKEN_URI`" >nul 2>&1"
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}
function Remove-InstallToken {
    cmd /c "aws s3 rm `"$TOKEN_URI`" >nul 2>&1"
    cmd /c exit 0
}

# --- Persistence layout -------------------------------------------------------
$MOUNT = [Environment]::GetEnvironmentVariable("DEADLINE_PERSISTENT_MOUNT", "Machine")
$PERSIST = -not [string]::IsNullOrEmpty($MOUNT)
if ($PERSIST) {
    Write-Host "Persistent volume: $MOUNT"
    $SW = "$MOUNT\Software"; $DATA = "$MOUNT\SoftwareData"
    $GRAFT = "$MOUNT\SoftwareRegistry\graft"; $STATE = "$MOUNT\.install-state.json"
} else { Write-Host "No persistent volume - plain install to C:" }

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
    # Compare installer by basename so re-staging the same zip in a different bucket
    # (e.g. shared bucket vs pv-cache copy) does not invalidate a good volume.
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
    $setupDir = if ($PERSIST) { "$MOUNT\installers" } else { "C:\3dsmax_setup" }
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
    Write-Host "3dsmaxbatch responds OK"
}

# --- S3 zip tier --------------------------------------------------------------
# Note on paths: never pass `-C "D:\"` - the trailing backslash before the closing
# quote is eaten by Windows argv parsing and bsdtar sees a broken path. Forward
# slashes are safe: `-C "D:/"` (learned live 2026-08-04: "tar create failed: 1").
function Invoke-Tar([string]$argLine, [string]$errCtx) {
    $errFile = "$env:TEMP\tar-err.txt"
    cmd /c "tar.exe $argLine 2>`"$errFile`""
    if ($LASTEXITCODE -ne 0) {
        $err = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' '
        throw "$errCtx failed ($LASTEXITCODE): $err"
    }
}
function Publish-S3Zip {
    # Zip {Software, SoftwareData, SoftwareRegistry, .install-state.json} - the payload,
    # registry graft (junction-target files + .reg + service JSON) and state marker.
    # Excludes installers\ (5+ GiB of re-downloadable media). tar.exe = bsdtar, ships
    # on Windows Server 2019+; -a picks zip format from the extension.
    # The licensing services hold file locks inside the payload while running - stop
    # them for the duration of the archive, then restart.
    $zipLocal = "$MOUNT\pv-payload.zip"
    if (Test-Path $zipLocal) { Remove-Item $zipLocal -Force }
    $running = @()
    foreach ($s in $ServiceNames) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { $running += $s; Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    }
    try {
        $t = Get-Date
        $mountFwd = $MOUNT.TrimEnd('\') + '/'
        Invoke-Tar "-a -cf `"$zipLocal`" -C `"$mountFwd`" Software SoftwareData SoftwareRegistry .install-state.json" "tar create"
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
    $zipLocal = "$MOUNT\pv-payload.zip"
    $t = Get-Date
    Invoke-Native "aws s3 cp --no-progress `"$ZIP_URI`" `"$zipLocal`"" "zip download"
    Write-Duration $t "Zip download"
    $t = Get-Date
    $mountFwd = $MOUNT.TrimEnd('\') + '/'
    Invoke-Tar "-xf `"$zipLocal`" -C `"$mountFwd`"" "tar extract"
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

if (-not $PERSIST) {
    Install-3dsMax; Set-EnvContract; Install-Adaptor; Test-Render
    Write-Duration $t0 "Total (no-PV install)"; exit 0
}

# Tier 1: PV-WARM
if (Test-StateValid) {
    Write-Host "=== PV-WARM boot: grafting cached install ==="
    try {
        Invoke-Graft
        Write-Duration $t0 "Total (PV-warm graft)"
        # Opportunistic S3 seed so other AZs never pay a cold install.
        if (-not (Test-S3Object $ZIP_URI)) {
            if (Get-InstallClaim) {
                Write-Host "=== Seeding S3 zip from this volume (one-time) ==="
                try { Publish-S3Zip } catch { Write-Host "WARNING: S3 seed failed (non-fatal): $_" }
                Remove-InstallToken
            }
        }
        exit 0
    } catch {
        Write-Host "WARNING: graft failed ($_). Invalidating volume cache."
        Remove-Item $STATE -Force -ErrorAction SilentlyContinue
    }
}

# Tier 2: S3-WARM
if (Test-S3Object $ZIP_URI) {
    Write-Host "=== S3-WARM boot: restoring volume from S3 zip ==="
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

# Tier 3: COLD (token-guarded) or WAIT
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
        if (Get-InstallClaim) { $claimed = $true; break }   # stale-token takeover
    }
    if (-not $claimed) { throw "timed out waiting for concurrent install to publish the S3 zip" }
}

Write-Host "=== COLD boot: installing to persistent volume ==="
try {
    Initialize-Junctions -CreateTargets $true
    Install-3dsMax
    Export-InstallerState
    Set-EnvContract
    Install-Adaptor
    Write-StateFile
    Test-Render
    Write-Host "=== Publishing S3 zip for other workers/AZs ==="
    try { Publish-S3Zip } catch { Write-Host "WARNING: S3 publish failed (non-fatal): $_" }
} finally {
    Remove-InstallToken
}
Write-Duration $t0 "Total (cold install + capture + publish)"
exit 0
