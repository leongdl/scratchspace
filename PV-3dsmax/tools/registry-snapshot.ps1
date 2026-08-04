<#
.SYNOPSIS
Registry + service snapshot, diff, export, and apply tool for the PV-3dsmax project.

Used two ways:
 1. DISCOVERY (M0 / SSM iteration): snapshot before and after running the 3ds Max and
    renderer installers, then diff to learn exactly which registry keys and Windows
    services the installers create. This answers the open question from PR #173
    ("which Autodesk registry keys are required?") empirically.
 2. WARM-BOOT GRAFT (M2+): export the vendor subtrees discovered in the diff to .reg
    files on the persistent volume, then apply them onto a fresh C: on later boots.

.USAGE
  # Take a snapshot (writes <OutDir>\<Label>-<timestamp>.txt + services JSON)
  .\registry-snapshot.ps1 snapshot -Label before
  ... run installers ...
  .\registry-snapshot.ps1 snapshot -Label after

  # Diff two snapshots (writes a report next to the After file)
  .\registry-snapshot.ps1 diff -Before .\snapshots\before-....txt -After .\snapshots\after-....txt

  # Export vendor registry subtrees to .reg files
  .\registry-snapshot.ps1 export -OutDir E:\SoftwareRegistry

  # Apply exported .reg files + recreate services (the warm-boot graft)
  .\registry-snapshot.ps1 apply -RegDir E:\SoftwareRegistry

.NOTES
Run from an elevated PowerShell. Snapshots of HKLM:\SOFTWARE can take a few minutes.
The full-walk snapshot is a discovery tool; the production host config should only
run 'export'/'apply' on the confirmed vendor subtrees.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('snapshot', 'diff', 'export', 'apply')]
    [string]$Command,

    # snapshot
    [string]$Label = 'snapshot',
    [string]$OutDir = "$PSScriptRoot\snapshots",
    [switch]$IncludeHKCU,   # close test gap G1: installers sometimes write to the running user's hive

    # diff
    [string]$Before,
    [string]$After,

    # export / apply
    [string]$RegDir,
    [string[]]$Subtrees = @(
        # Initial hypothesis; correct this list from the M0 diff output.
        'HKLM\SOFTWARE\Autodesk',
        'HKLM\SOFTWARE\WOW6432Node\Autodesk',
        'HKLM\SOFTWARE\Chaos Group',
        'HKLM\SOFTWARE\WOW6432Node\Chaos Group',
        'HKLM\SOFTWARE\Chaos',
        'HKLM\SOFTWARE\WOW6432Node\Chaos'
    ),
    # Service-name patterns to snapshot/recreate (generalizes the AE script's '*Red Giant*' filter)
    [string[]]$ServicePatterns = @('*Adsk*', '*Autodesk*', '*Chaos*', '*vrlsvc*', '*vrl*service*')
)

$ErrorActionPreference = 'Stop'

function New-Dir([string]$p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

# ---------------------------------------------------------------------------
# snapshot: one line per registry key/value:  <keyPath>|<valueName>|<kind>|<sha1-of-data>
# Hashing keeps snapshot files small and diffable while still detecting data changes.
# ---------------------------------------------------------------------------
function Get-ValueHash($data) {
    if ($null -eq $data) { return 'null' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($data | Out-String))
    $sha = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 12) }
    finally { $sha.Dispose() }
}

function Write-HiveSnapshot([string]$hivePath, [IO.StreamWriter]$writer) {
    # Iterative stack walk; Get-ChildItem -Recurse chokes on access-denied subkeys.
    $stack = [Collections.Stack]::new()
    $stack.Push($hivePath)
    while ($stack.Count -gt 0) {
        $path = $stack.Pop()
        try { $key = Get-Item -LiteralPath $path -ErrorAction Stop } catch { continue }

        $writer.WriteLine("$path||key|present")
        foreach ($name in $key.GetValueNames()) {
            try {
                $kind = $key.GetValueKind($name)
                $hash = Get-ValueHash $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
                $display = if ($name -eq '') { '(Default)' } else { $name }
                $writer.WriteLine("$path|$display|$kind|$hash")
            } catch { $writer.WriteLine("$path|$name|error|unreadable") }
        }
        foreach ($sub in $key.GetSubKeyNames()) {
            $stack.Push((Join-Path $path $sub))
        }
    }
}

function Invoke-Snapshot {
    New-Dir $OutDir
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $regFile = Join-Path $OutDir "$Label-$stamp.txt"
    $svcFile = Join-Path $OutDir "$Label-$stamp.services.json"

    $hives = @('HKLM:\SOFTWARE', 'HKLM:\SYSTEM\CurrentControlSet\Services')
    if ($IncludeHKCU) { $hives += 'HKCU:\SOFTWARE' }

    Write-Host "Snapshotting registry ($($hives -join ', ')) -> $regFile"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $writer = [IO.StreamWriter]::new($regFile, $false, [Text.Encoding]::UTF8)
    try { foreach ($h in $hives) { Write-HiveSnapshot $h $writer } }
    finally { $writer.Dispose() }

    Write-Host "Snapshotting services -> $svcFile"
    Get-CimInstance Win32_Service |
        Select-Object Name, DisplayName, PathName, StartMode, State, StartName, Description |
        ConvertTo-Json -Depth 3 | Out-File $svcFile -Encoding utf8

    $sw.Stop()
    Write-Host ("Snapshot complete in {0:mm\:ss}. Lines: {1}" -f $sw.Elapsed, (Get-Content $regFile | Measure-Object -Line).Lines)
    Write-Host "Registry: $regFile"
    Write-Host "Services: $svcFile"
}

# ---------------------------------------------------------------------------
# diff: added / removed / modified lines between two snapshots, grouped by prefix.
# ---------------------------------------------------------------------------
function Invoke-Diff {
    if (-not ($Before -and $After)) { throw "diff requires -Before and -After snapshot files" }

    Write-Host "Loading snapshots..."
    $beforeMap = @{}
    foreach ($line in [IO.File]::ReadLines($Before)) {
        $idx = $line.LastIndexOf('|')
        if ($idx -gt 0) { $beforeMap[$line.Substring(0, $idx)] = $line.Substring($idx + 1) }
    }
    $afterMap = @{}
    foreach ($line in [IO.File]::ReadLines($After)) {
        $idx = $line.LastIndexOf('|')
        if ($idx -gt 0) { $afterMap[$line.Substring(0, $idx)] = $line.Substring($idx + 1) }
    }

    $added = [Collections.Generic.List[string]]::new()
    $modified = [Collections.Generic.List[string]]::new()
    $removed = [Collections.Generic.List[string]]::new()

    foreach ($k in $afterMap.Keys) {
        if (-not $beforeMap.ContainsKey($k)) { $added.Add($k) }
        elseif ($beforeMap[$k] -ne $afterMap[$k]) { $modified.Add($k) }
    }
    foreach ($k in $beforeMap.Keys) {
        if (-not $afterMap.ContainsKey($k)) { $removed.Add($k) }
    }

    $report = [IO.Path]::ChangeExtension($After, $null).TrimEnd('.') + '.diff.txt'
    $out = [IO.StreamWriter]::new($report, $false, [Text.Encoding]::UTF8)
    try {
        foreach ($section in @(@('ADDED', $added), @('MODIFIED', $modified), @('REMOVED', $removed))) {
            $name, $list = $section
            $out.WriteLine("=== $name ($($list.Count)) ===")
            # Group by top 3 path segments so the vendor subtrees jump out.
            $list | Group-Object { ($_ -split '\\')[0..([Math]::Min(3, ($_ -split '\\').Count - 1))] -join '\' } |
                Sort-Object Count -Descending | ForEach-Object {
                    $out.WriteLine("  [$($_.Count)] $($_.Name)")
                }
            $out.WriteLine('')
            $out.WriteLine("--- full $name list ---")
            $list | Sort-Object | ForEach-Object { $out.WriteLine("  $_") }
            $out.WriteLine('')
        }
    } finally { $out.Dispose() }

    Write-Host "Added: $($added.Count)  Modified: $($modified.Count)  Removed: $($removed.Count)"
    Write-Host "Report: $report"
    Write-Host ""
    Write-Host "Top added prefixes (candidates for the export subtree list):"
    $added | Group-Object { ($_ -split '\\')[0..([Math]::Min(2, ($_ -split '\\').Count - 1))] -join '\' } |
        Sort-Object Count -Descending | Select-Object -First 15 |
        ForEach-Object { Write-Host ("  [{0,6}] {1}" -f $_.Count, $_.Name) }

    # Diff the service snapshots too, if present alongside.
    $beforeSvc = [IO.Path]::ChangeExtension($Before, $null).TrimEnd('.') + '.services.json'
    $afterSvc = [IO.Path]::ChangeExtension($After, $null).TrimEnd('.') + '.services.json'
    if ((Test-Path $beforeSvc) -and (Test-Path $afterSvc)) {
        $b = (Get-Content $beforeSvc -Raw | ConvertFrom-Json).Name
        $a = Get-Content $afterSvc -Raw | ConvertFrom-Json
        $newSvcs = $a | Where-Object { $b -notcontains $_.Name }
        if ($newSvcs) {
            Write-Host ""
            Write-Host "New services installed:"
            $newSvcs | ForEach-Object { Write-Host "  $($_.Name) [$($_.StartMode)] -> $($_.PathName)" }
        }
    }
}

# ---------------------------------------------------------------------------
# export: reg.exe export of the vendor subtrees + service JSON for the graft.
# ---------------------------------------------------------------------------
function Invoke-Export {
    $dir = if ($RegDir) { $RegDir } else { $OutDir }
    New-Dir $dir
    foreach ($subtree in $Subtrees) {
        $safe = ($subtree -replace '[\\:]', '_') + '.reg'
        $dest = Join-Path $dir $safe
        # reg.exe query to check existence quietly; not every hypothesized subtree exists on every version
        reg.exe query "$subtree" /ve *> $null
        if ($LASTEXITCODE -eq 0) {
            reg.exe export "$subtree" "$dest" /y | Out-Null
            Write-Host "Exported $subtree -> $dest"
        } else {
            Write-Host "Skipped (not present): $subtree"
        }
    }

    # Service definitions for matching patterns, one JSON per service (AE-script style).
    $svcDir = Join-Path $dir 'services'
    New-Dir $svcDir
    $services = Get-CimInstance Win32_Service | Where-Object {
        $svc = $_; ($ServicePatterns | Where-Object { $svc.Name -like $_ -or $svc.DisplayName -like $_ }).Count -gt 0
    }
    foreach ($svc in $services) {
        @{
            Name = $svc.Name; DisplayName = $svc.DisplayName; PathName = $svc.PathName
            StartMode = $svc.StartMode; Description = $svc.Description; StartName = $svc.StartName
        } | ConvertTo-Json | Out-File (Join-Path $svcDir "$($svc.Name).json") -Encoding utf8
        Write-Host "Captured service: $($svc.Name) [$($svc.StartMode)]"
    }
    if (-not $services) { Write-Host "WARNING: no services matched patterns: $($ServicePatterns -join ', ')" }
}

# ---------------------------------------------------------------------------
# apply: the warm-boot graft. Import .reg files, recreate + start services.
# ---------------------------------------------------------------------------
function Invoke-Apply {
    if (-not $RegDir) { throw "apply requires -RegDir pointing at the export directory" }

    foreach ($regFile in Get-ChildItem "$RegDir\*.reg" -ErrorAction SilentlyContinue) {
        reg.exe import "$($regFile.FullName)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg import failed for $($regFile.Name)" }
        Write-Host "Imported $($regFile.Name)"
    }

    $svcDir = Join-Path $RegDir 'services'
    if (Test-Path $svcDir) {
        foreach ($file in Get-ChildItem "$svcDir\*.json") {
            $svc = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                $startType = switch ($svc.StartMode) {
                    'Auto' { 'auto' } 'Manual' { 'demand' } 'Disabled' { 'disabled' } default { 'auto' }
                }
                sc.exe create $svc.Name binPath= "$($svc.PathName)" start= $startType DisplayName= "$($svc.DisplayName)" | Out-Null
                if ($svc.Description) { sc.exe description $svc.Name "$($svc.Description)" | Out-Null }
                Write-Host "Registered service: $($svc.Name) [$startType]"
            }
            # Policy decisions from DESIGN.md:
            #  - AdAppMgrSvc (Autodesk Access): keep registered but do NOT start; render workers don't need it.
            if ($svc.Name -eq 'AdAppMgrSvc') {
                sc.exe config $svc.Name start= disabled | Out-Null
                Write-Host "  -> left disabled (Autodesk Access not needed on render workers)"
                continue
            }
            if ($svc.StartMode -eq 'Auto') {
                try { Start-Service -Name $svc.Name -ErrorAction Stop; Write-Host "  -> started" }
                catch { Write-Host "  WARNING: failed to start $($svc.Name): $_" }
            }
        }
    } else {
        Write-Host "WARNING: no services directory at $svcDir"
    }
}

switch ($Command) {
    'snapshot' { Invoke-Snapshot }
    'diff'     { Invoke-Diff }
    'export'   { Invoke-Export }
    'apply'    { Invoke-Apply }
}
