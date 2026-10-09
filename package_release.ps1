# Build a shareable snapshot without old backups, private designs or logs.
[CmdletBinding()]
param([string]$ReleaseLabel = '2026.10.09-two-files', [switch]$RebuildMouseHelper)
$ErrorActionPreference = 'Stop'
$quickReferenceName = -join (@(0x5FEB,0x6377,0x64CD,0x4F5C,0x901F,0x67E5) | ForEach-Object { [char]$_ })
$quickReferenceName += '.md' # ASCII script stays readable by Windows PowerShell 5.1.
if ($ReleaseLabel -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw 'ReleaseLabel must be a short filename-safe label.'
}

$runtimeNames = @('OrCADQuickTools.tcl', 'OrCADWheelZoom.exe')
$sourceNames = @(
    'OrCADQuickTools.tcl', 'src/OrCADQuickTools.core.tcl',
    'src/OrCADPinNetXlsx.tcl', 'src/OrCADOffPageToggle.tcl', 'src/OrCADWheelZoom.tcl',
    'OrCADWheelZoom.cs', 'OrCADWheelZoom.manifest',
    'build_tcl_bundle.ps1', 'build_wheel_zoom.ps1', 'package_release.ps1',
    'test_page_auto_annotate.tcl', 'test_offpage_toggle.tcl', 'test_wheel_zoom.tcl', 'test_signals_navigation.tcl',
    'test_wheel_zoom_native.ps1', 'test_wheel_zoom_native.cs',
    'test_tcl_bundle.ps1', 'test_tcl_bundle.tcl',
    'README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'EXTENDING.md',
    $quickReferenceName, '.gitattributes', '.gitignore'
)
$documentNames = @('README.md', 'CHANGELOG.md', 'EXTENDING.md', $quickReferenceName)

& (Join-Path $PSScriptRoot 'build_tcl_bundle.ps1')
if ($RebuildMouseHelper -or -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'OrCADWheelZoom.exe'))) {
    & (Join-Path $PSScriptRoot 'build_wheel_zoom.ps1')
}
foreach ($fileName in ($runtimeNames + $sourceNames + $documentNames | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $fileName) -PathType Leaf)) {
        throw "Required release file missing: $fileName"
    }
}

$outputRoot = Join-Path $PSScriptRoot 'dist'
$packageName = 'OrCADQuickTools-' + $ReleaseLabel + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$packageRoot = Join-Path $outputRoot $packageName
$archivePath = Join-Path $outputRoot ($packageName + '.zip')
$runtimeArchivePath = Join-Path $outputRoot ($packageName + '-runtime.zip')
if ((Test-Path -LiteralPath $packageRoot) -or (Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $runtimeArchivePath)) {
    throw 'Release destination already exists; no files were overwritten.'
}
$runtimeRoot = Join-Path $packageRoot 'capAutoLoad'
$sourceRoot = Join-Path $packageRoot 'source'
New-Item -ItemType Directory -Path $runtimeRoot, $sourceRoot -Force | Out-Null

foreach ($fileName in $runtimeNames) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $runtimeRoot $fileName)
}
foreach ($fileName in $sourceNames) {
    $sourceDestination = Join-Path $sourceRoot $fileName
    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($sourceDestination)) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination $sourceDestination
}
foreach ($fileName in $documentNames) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $packageRoot $fileName)
}

$hashLines = foreach ($releaseFile in (Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Sort-Object FullName)) {
    $relativeName = $releaseFile.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
    (Get-FileHash -LiteralPath $releaseFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relativeName
}
$hashLines | Set-Content -LiteralPath (Join-Path $packageRoot 'SHA256SUMS.txt') -Encoding UTF8
Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
Compress-Archive -LiteralPath @($runtimeNames | ForEach-Object { Join-Path $runtimeRoot $_ }) -DestinationPath $runtimeArchivePath -CompressionLevel Optimal
Write-Output ('Share package: ' + $archivePath)
Write-Output ('Two-file install ZIP: ' + $runtimeArchivePath)
Write-Output ('Runtime files: ' + $runtimeRoot)
Write-Output ('SHA256: ' + (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash)
