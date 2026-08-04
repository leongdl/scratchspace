$ErrorActionPreference = 'Continue'
Write-Host "=== Identity ==="
whoami
Write-Host "=== DEADLINE_PERSISTENT_MOUNT (Machine) ==="
[Environment]::GetEnvironmentVariable('DEADLINE_PERSISTENT_MOUNT','Machine')
Write-Host "=== Volumes ==="
Get-Volume | Where-Object { $_.DriveLetter } | Format-Table DriveLetter, FileSystemLabel, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}} -AutoSize | Out-String
Write-Host "=== D: contents ==="
Get-ChildItem D:\ -Force -ErrorAction SilentlyContinue | Select-Object Name, Mode | Format-Table -AutoSize | Out-String
Write-Host "=== Write test on D: ==="
"test $(Get-Date)" | Out-File D:\pv-write-test.txt
Get-Content D:\pv-write-test.txt
Write-Host "=== .NET Framework 4.8 check ==="
$rel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
Write-Host "NDP v4 Full Release: $rel (>= 528040 means 4.8)"
Write-Host "=== Disk space C: ==="
Get-PSDrive C | Select-Object @{n='UsedGB';e={[math]::Round($_.Used/1GB)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB)}} | Format-Table -AutoSize | Out-String
