$ErrorActionPreference = 'Stop'

# --- Create junctions so the installer writes through to the persistent volume ---
$junctions = @(
    @{ Link = 'C:\Program Files\Autodesk';                          Target = 'D:\Software\Autodesk' }
    @{ Link = 'C:\ProgramData\Autodesk';                            Target = 'D:\SoftwareData\Autodesk' }
    @{ Link = 'C:\Program Files\Common Files\Autodesk Shared';      Target = 'D:\Software\AutodeskShared' }
    @{ Link = 'C:\Program Files (x86)\Common Files\Autodesk Shared'; Target = 'D:\Software\AutodeskSharedX86' }
)
foreach ($j in $junctions) {
    if (Test-Path $j.Link) {
        $item = Get-Item $j.Link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Write-Host "Exists: $($j.Link)"; continue }
        Remove-Item $j.Link -Recurse -Force
    }
    $parent = Split-Path $j.Link -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    New-Item -ItemType Directory -Path $j.Target -Force | Out-Null
    New-Item -ItemType Junction -Path $j.Link -Target $j.Target | Out-Null
    Write-Host "Junction: $($j.Link) -> $($j.Target)"
}

# --- Extract the installer on D: (keeps C: clean; extraction is IO-bound) ---
$zip = 'D:\installers\3dsMax2025.zip'
$dest = 'D:\installers\3dsmax2025'
if (Test-Path "$dest\Setup.exe") {
    Write-Host "Already extracted."
} else {
    Write-Host "Extracting $zip ..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    $sw.Stop()
    Write-Host ("Extracted in {0:mm\:ss}" -f $sw.Elapsed)
}
# Locate Setup.exe (zip may nest a folder)
$setup = Get-ChildItem -Path $dest -Filter Setup.exe -Recurse | Select-Object -First 1
if (-not $setup) { throw "Setup.exe not found under $dest" }
Write-Host "Setup.exe: $($setup.FullName)"
