[CmdletBinding()]
param(
    [Alias('Sdk')][string]$SdkPath = $env:CONNECTIQ_SDK,
    [Alias('Key')][string]$DeveloperKey = $env:DEVELOPER_KEY,
    [string]$SettingsFile,
    [string]$Device = 'fenix847mm',
    [ValidateSet('beta', 'release')][string]$Channel = 'release',
    [Alias('Export')][switch]$Package,
    [switch]$Run,
    [switch]$PrintSdk
)
$ErrorActionPreference = 'Stop'
if ($Package -and ($SettingsFile -or $Run)) { throw 'Do not combine -Package with personal settings or -Run.' }
if (-not $SdkPath) {
    $config = Join-Path $env:APPDATA 'Garmin/ConnectIQ/current-sdk.cfg'
    if (Test-Path -LiteralPath $config) { $SdkPath = (Get-Content -LiteralPath $config -Raw).Trim() }
    else { $SdkPath = Join-Path $PSScriptRoot '.tools/sdk' }
}
$SdkPath = (Resolve-Path -LiteralPath $SdkPath).Path
$compiler = Join-Path $SdkPath 'bin/monkeyc.bat'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'SDK must contain bin/monkeyc.bat.' }
if ($PrintSdk) { Write-Output $SdkPath; return }
$manifest = Join-Path $PSScriptRoot 'manifest.xml'
$application = ([xml](Get-Content -LiteralPath $manifest -Raw)).manifest.application
$appId = if ($Channel -eq 'beta') { $env:GARMIN_BETA_APP_ID } else { $env:GARMIN_RELEASE_APP_ID }
if (!$appId -and $Channel -eq 'release') { $appId = $application.id }
if ($appId -notmatch '\A[0-9a-fA-F]{32}\z') { throw "Set a 32-digit hexadecimal GARMIN_$($Channel.ToUpperInvariant())_APP_ID." }
$strings = [xml](Get-Content -LiteralPath "$PSScriptRoot/resources/strings/strings.xml" -Raw)
$name = ($strings.strings.string | Where-Object id -eq 'Voicenotes').InnerText
if ($application.name -cne '@Strings.Voicenotes' -or $name -cne 'Voicenotes') { throw 'The application name must be exactly Voicenotes.' }
if (-not $Package -and $Device -notin $application.products.product.id) { throw "Unsupported device '$Device'. Choose a product ID from manifest.xml." }
if ($SettingsFile) {
    $config = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
    $targetValues = @{}
    foreach ($suffix in '', '2', '3') {
        $urlKey = "serverUrl$suffix"
        $tokenKey = "serverToken$suffix"
        $url = $config.$urlKey
        $token = $config.$tokenKey
        if (($null -eq $url -or $url -ceq '') -and ($null -eq $token -or $token -ceq '')) { continue }
        $server = $null
        if ($url -isnot [string] -or -not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$server) -or
            $server.Scheme -ne 'https' -or -not $server.Host -or $url -match '[?#@\s]' -or
            $token -isnot [string] -or $token.Length -lt 32 -or $token -match '[^\x21-\x7e]') {
            throw "Settings need an HTTPS $urlKey and a printable ASCII $tokenKey of at least 32 characters."
        }
        $targetValues[$urlKey] = $url.TrimEnd('/')
        $targetValues[$tokenKey] = $token
    }
    if (!$targetValues.Count) { throw 'Settings need at least one sync target.' }
    if ($null -ne $config.autoUpload -and $config.autoUpload -isnot [bool]) { throw 'autoUpload must be true or false.' }
}
$private = Join-Path $PSScriptRoot 'private'
$output = Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force -Path $private, $output | Out-Null
if (-not $DeveloperKey) {
    $DeveloperKey = Join-Path $private 'developer_key.der'
    $legacyKey = Join-Path $PSScriptRoot '.tools/developer.der'
    if (-not (Test-Path -LiteralPath $DeveloperKey) -and (Test-Path -LiteralPath $legacyKey)) { Copy-Item -LiteralPath $legacyKey -Destination $DeveloperKey }
}
$DeveloperKey = [IO.Path]::GetFullPath($DeveloperKey)
if (-not (Test-Path -LiteralPath $DeveloperKey)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $DeveloperKey) | Out-Null
    $rsa = New-Object System.Security.Cryptography.RSACng 4096
    try { [IO.File]::WriteAllBytes($DeveloperKey, $rsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)) }
    finally { $rsa.Dispose() }
}
$jungle = Join-Path $PSScriptRoot 'monkey.jungle'
if ($appId -ne $application.id) {
    $channelManifest = Join-Path $private "manifest-$Channel.xml"
    $channelJungle = Join-Path $private "manifest-$Channel.jungle"
    [xml]$channelXml = Get-Content -LiteralPath $manifest -Raw
    $channelXml.manifest.application.SetAttribute('id', $appId)
    $channelXml.Save($channelManifest)
    "project.manifest = manifest-$Channel.xml" | Set-Content -LiteralPath $channelJungle -Encoding Ascii
    $jungle = $channelJungle
}
$jungle = "$jungle;$PSScriptRoot/resources.jungle"
if ($SettingsFile) {
    $resources = Join-Path $private 'resources'
    New-Item -ItemType Directory -Force -Path $resources | Out-Null
    Copy-Item -Path "$PSScriptRoot/resources/*" -Destination $resources -Recurse -Force
    $properties = [xml](Get-Content -LiteralPath "$resources/settings/properties.xml" -Raw)
    foreach ($property in $properties.properties.property) {
        if ($targetValues.ContainsKey($property.id)) { $property.InnerText = $targetValues[$property.id] }
    }
    ($properties.properties.property | Where-Object id -eq 'autoUpload').InnerText = ([bool]$config.autoUpload).ToString().ToLowerInvariant()
    $properties.Save("$resources/settings/properties.xml")
    $personalJungle = Join-Path $private 'Voicenotes-personal.jungle'
    $root = $PSScriptRoot.Replace('\', '/')
    $jungleContent = @"
base.resourcePath = $root/private/resources
"@
    [IO.File]::WriteAllText($personalJungle, $jungleContent + "`n", (New-Object System.Text.UTF8Encoding $false))
    $jungle = "$jungle;$personalJungle"
}
$artifactName = if ($Channel -eq 'beta') { 'Voicenotes-beta' } else { 'Voicenotes' }
$extension = if ($Package) { 'iq' } else { 'prg' }
$artifact = Join-Path $output "$artifactName.$extension"
$arguments = @('-f', $jungle, '-o', $artifact, '-y', $DeveloperKey, '-w', '-r')
if ($Package) { $arguments += '-e' } else { $arguments += @('-d', $Device) }
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw "Connect IQ build failed ($LASTEXITCODE)." }
Write-Output $artifact
if ($Run) {
    & "$SdkPath/bin/monkeydo.bat" $artifact $Device
    if ($LASTEXITCODE -ne 0) { throw "Simulator launch failed ($LASTEXITCODE)." }
}
