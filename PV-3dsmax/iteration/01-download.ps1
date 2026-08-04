$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path D:\installers | Out-Null
$url = @'
<PRESIGNED-URL-REGENERATE: aws s3 presign s3://common-bealinerezpackage-resources-bucket/3dsmax/2025/3dsMax2025.zip --expires-in 7200 --region us-west-2>
'@
$url = $url.Trim()
Write-Host "Downloading 3dsMax2025.zip to D:\installers ..."
$sw = [Diagnostics.Stopwatch]::StartNew()
curl.exe -sS -L -o D:\installers\3dsMax2025.zip $url
if ($LASTEXITCODE -ne 0) { throw "curl failed: $LASTEXITCODE" }
$sw.Stop()
$size = (Get-Item D:\installers\3dsMax2025.zip).Length
Write-Host ("Downloaded {0:N0} bytes in {1:mm\:ss}" -f $size, $sw.Elapsed)
