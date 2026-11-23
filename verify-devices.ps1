# Compile all installed manifest targets without changing the release manifest.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$sdk = & "$PSScriptRoot/build.ps1" -PrintSdk
$key = if ($env:DEVELOPER_KEY) { $env:DEVELOPER_KEY } else { Join-Path $PSScriptRoot 'private/developer_key.der' }
if (!(Test-Path -LiteralPath $key)) { throw 'Run build.ps1 first to create the signing key.' }
[xml]$manifest = Get-Content manifest.xml
$devices = Join-Path $env:APPDATA 'Garmin\ConnectIQ\Devices'
$missing = @()
foreach ($product in @($manifest.manifest.application.products.product)) {
    if (!(Test-Path (Join-Path $devices ($product.id + '\compiler.json')))) {
        $missing += $product.id
        $product.ParentNode.RemoveChild($product) | Out-Null
    }
}
if ($missing.Count) { Write-Warning ('Unverified profiles: ' + ($missing -join ', ')) }
New-Item -ItemType Directory -Force .tools\verification, bin | Out-Null
$manifest.Save((Join-Path $PSScriptRoot '.tools\verification\manifest.xml'))
@'
project.manifest = manifest.xml
'@ | Set-Content .tools\verification\monkey.jungle
& "$sdk\bin\monkeyc.bat" -f 'monkey.jungle;.tools/verification/monkey.jungle' -y $key -e -o bin\Voicenotes-installed-profiles.iq -w
if ($LASTEXITCODE -ne 0) { throw 'Device verification failed' }
Write-Output ('Compiled profiles: ' + $manifest.manifest.application.products.product.Count)
if ($missing.Count) { Write-Warning 'This verification package is incomplete; do not use it as the full release.' }
