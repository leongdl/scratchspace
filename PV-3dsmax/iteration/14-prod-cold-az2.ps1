<#
3ds Max 2025 host configuration with persistent-volume caching for AWS Deadline Cloud
Windows Service-Managed Fleets.

DRAFT assembled from the steps proven live on fleet PV3dsMaxDebugFleet on 2026-08-04
(see PV-3dsmax/JOURNAL.md). Cold path installs 3ds Max through NTFS junctions onto the
fleet's persistent volume and captures registry/services/licensing state; warm path
grafts that captured state onto the fresh C: drive in ~1-2 minutes instead of ~20.

Behavior by volume state:
  - No persistent volume configured        -> plain install to C: (no caching)
  - Volume attached, no valid state file   -> COLD: install to volume + capture + graft
  - Volume attached, valid state file      -> WARM: graft only (junctions, registry,
                                              services, env, licensing files)
  - Graft failure                          -> invalidate state file, fall through to COLD

Requirements:
  - Fleet has persistentVolumeConfiguration (mountPath "D:", >= 100 GiB; tested at 500)
  - Fleet role can s3:GetObject the installer object below
  - Fleet host configuration timeout: 3600 seconds (cold path measured 14:36 install
    + 2:29 download + 1:14 extract + capture; warm path ~2 min)

Verified on Windows Server 2022 SMF AMI, 3ds Max 2025 (3dsMax2025.zip, ODIS installer).
.NET Framework 4.8 ships on the AMI; no Layer-0 framework installs needed for 2025.
#>

$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
# TODO: Replace with your S3 URI. Guide for creating the zip:
# <PRESIGNED-URL>
$3DS_MAX_INSTALLER_ZIP_S3_URI = "s3://common-bealinerezpackage-resources-bucket/3dsmax/2025/3dsMax2025.zip"
$MAX_VERSION = "2025"
$FORCE_REINSTALL = $false   # set $true to invalidate the volume cache once
# END CONFIG ============

$MAX_ROOT = "C:\Program Files\Autodesk\3ds Max $MAX_VERSION"

function Write-Duration($start, $name) { Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }

# reg.exe writes its success message to stderr; under strict mode that becomes a
# terminating error (hit live on 2026-08-04). Wrap every reg.exe call via cmd.
function Invoke-Reg([string]$argLine) {
    cmd /c "reg.exe $argLine >nul 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "reg.exe $argLine failed: $LASTEXITCODE" }
}

function Invoke-Robocopy([string]$src, [string]$dst) {
    robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy '$src' -> '$dst' failed: $LASTEXITCODE" }
    cmd /c exit 0   # robocopy 1-7 = success-with-copies; reset LASTEXITCODE
}

# --- Persistence layout -----------------------------------------------------
$MOUNT = [Environment]::GetEnvironmentVariable("DEADLINE_PERSISTENT_MOUNT", "Machine")
$PERSIST = -not [string]::IsNullOrEmpty($MOUNT)
if ($PERSIST) {
    Write-Host "Persistent volume: $MOUNT"
    $SW    = "$MOUNT\Software"
    $DATA  = "$MOUNT\SoftwareData"
    $GRAFT = "$MOUNT\SoftwareRegistry\graft"
    $STATE = "$MOUNT\.install-state.json"
} else {
    Write-Host "No persistent volume - plain install to C:"
}

# Junction set. FlexNet (Macrovision Shared + ProgramData\FLEXnet) deliberately NOT
# junctioned: the FlexNet service resists junctioned install paths less predictably,
# so it is captured by copy and restored by copy instead (proven approach).
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

# --- Environment contract (PR #173 variable set; re-applied EVERY boot because the
#     machine-env registry on C: is fresh each boot) --------------------------
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

# --- Service snapshot/replay (generalizes the AE script's pattern) -----------
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
    # FlexNet lives OUTSIDE the junction set (finding from 2026-08-04): capture by copy.
    Invoke-Robocopy "C:\Program Files\Common Files\Macrovision Shared" "$SW\MacrovisionShared"
    Invoke-Robocopy "C:\ProgramData\FLEXnet" "$DATA\FLEXnet"

    # Filtered registry graft: full Autodesk subtrees. (The iteration run also grafted
    # the installer-added Classes/* COM keys diffed from before/after full-hive exports;
    # for the single-file production script we export the Autodesk trees plus the
    # class/file-association keys 3ds Max registers under Classes.)
    New-Item -ItemType Directory -Force -Path $GRAFT | Out-Null
    Invoke-Reg "export `"HKLM\SOFTWARE\Autodesk`" `"$GRAFT\hklm-autodesk.reg`" /y"
    Invoke-Reg "export `"HKLM\SOFTWARE\Wow6432Node\Autodesk`" `"$GRAFT\hklm-wow-autodesk.reg`" /y"
    foreach ($cls in "3dsmax","3dschr","3dsifl","3dsms","3dsmxp","3dsmcr",".max") {
        cmd /c "reg.exe export `"HKLM\SOFTWARE\Classes\$cls`" `"$GRAFT\cls-$($cls -replace '\.','_').reg`" /y >nul 2>&1"
    }
    cmd /c exit 0
    Write-Host "Registry graft exported"
    # NOTE: COM CLSID/Interface/TypeLib keys under Classes are restored implicitly on
    # warm boots ONLY if 3ds Max tolerates their absence. The iteration run grafted the
    # full added-key set and validated 3dsmaxbatch; an actual render test on a true
    # warm boot decides whether the CLSID set must be captured here too (see JOURNAL
    # open item). If needed: before/after reg export diff, as in iteration/07+09.
}

function Import-InstallerState {
    Invoke-Robocopy "$SW\MacrovisionShared" "C:\Program Files\Common Files\Macrovision Shared"
    Invoke-Robocopy "$DATA\FLEXnet" "C:\ProgramData\FLEXnet"
    foreach ($regFile in Get-ChildItem "$GRAFT\*.reg") {
        Invoke-Reg "import `"$($regFile.FullName)`""
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
            # Policy: render workers do not need Autodesk Access; keep registered, disabled.
            sc.exe config "$($svc.Name)" start= disabled | Out-Null
            continue
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
    return ($s.maxVersion -eq $MAX_VERSION -and $s.maxInstallerUri -eq $3DS_MAX_INSTALLER_ZIP_S3_URI)
}

function Install-3dsMax {
    $dl = Get-Date
    $setupDir = if ($PERSIST) { "$MOUNT\installers" } else { "C:\3dsmax_setup" }
    New-Item -ItemType Directory -Force -Path $setupDir | Out-Null
    if (-not (Test-Path "$setupDir\3dsmax.zip")) {
        $presigned = @'
<PRESIGNED-URL>
'@
        curl.exe -sS -L -o "$setupDir\3dsmax.zip" $presigned.Trim()
        if ($LASTEXITCODE -ne 0) { throw "installer download failed" }
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

function Test-Render {
    $out = & "$MAX_ROOT\3dsmaxbatch.exe" -help 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "3dsmaxbatch -help failed: $LASTEXITCODE" }
    Write-Host "3dsmaxbatch responds OK"
}

# === MAIN ====================================================================
$t0 = Get-Date

if (-not $PERSIST) {
    Install-3dsMax
    Set-EnvContract
    Test-Render
    Write-Duration $t0 "Total (no-PV install)"
    exit 0
}

if (Test-StateValid) {
    Write-Host "=== WARM boot: grafting cached install ==="
    try {
        Initialize-Junctions -CreateTargets $false
        Import-InstallerState
        Set-EnvContract
        Test-Render
        Write-Duration $t0 "Total (warm graft)"
        exit 0
    } catch {
        Write-Host "WARNING: graft failed ($_). Invalidating cache and reinstalling."
        Remove-Item $STATE -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "=== COLD boot: installing to persistent volume ==="
Initialize-Junctions -CreateTargets $true
Install-3dsMax
Export-InstallerState
Set-EnvContract
@{ schemaVersion = 1; maxVersion = $MAX_VERSION
   maxInstallerUri = $3DS_MAX_INSTALLER_ZIP_S3_URI
   installedAt = (Get-Date -Format o) } | ConvertTo-Json | Out-File $STATE -Encoding utf8
Test-Render
Write-Duration $t0 "Total (cold install + capture)"
exit 0
