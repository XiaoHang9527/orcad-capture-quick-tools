# Build a shareable snapshot without old backups, private designs or logs.
[CmdletBinding()]
param(
    [string]$ReleaseLabel,
    [switch]$RebuildMouseHelper,
    [string]$DeterministicCompiler,
    [switch]$PrepareDownload,
    [switch]$ListSourceFiles,
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'dist')
)
$ErrorActionPreference = 'Stop'
$bundleBuilder = Join-Path $PSScriptRoot 'build_tcl_bundle.ps1'
$releaseVersion = & $bundleBuilder -PrintVersion
if (-not $ReleaseLabel) { $ReleaseLabel = "$releaseVersion-public" }
$quickReferenceName = -join (@(0x5FEB,0x6377,0x64CD,0x4F5C,0x901F,0x67E5) | ForEach-Object { [char]$_ })
$quickReferenceName += '.md' # ASCII script stays readable by Windows PowerShell 5.1.
if ($ReleaseLabel -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw 'ReleaseLabel must be a short filename-safe label.'
}

$runtimeNames = @('OrCADQuickTools.tcl', 'OrCADWheelZoom.exe')
$modules = @(& $bundleBuilder -ListModules)
$sourceNames = $modules + @(
    'OrCADQuickTools.tcl',
    'OrCADWheelZoom.cs', 'OrCADWheelZoom.manifest',
    'build_tcl_bundle.ps1', 'build_wheel_zoom.ps1', 'package_release.ps1',
    'test_page_auto_annotate.tcl', 'test_offpage_toggle.tcl', 'test_offpage_session.tcl', 'test_wheel_zoom.tcl', 'test_signals_navigation.tcl', 'test_part_preview.tcl', 'test_design_pin_net.tcl',
    'test_wheel_zoom_native.ps1', 'test_wheel_zoom_native.cs',
    'test_tcl_bundle.ps1', 'test_tcl_bundle.tcl',
    'README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'EXTENDING.md',
    $quickReferenceName, '.gitattributes', '.gitignore'
)
$documentNames = @('README.md', 'CHANGELOG.md', 'EXTENDING.md', $quickReferenceName)
if ($ListSourceFiles) { $sourceNames; return }

if ($PrepareDownload) {
    $dirty = git -C $PSScriptRoot status --porcelain --untracked-files=normal
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Commit and review the source tree before preparing a public download.' }
    git -C $PSScriptRoot ls-files --error-unmatch -- @sourceNames | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'A required release source file is not tracked.' }
    if (-not $DeterministicCompiler) { throw 'Provide a Roslyn csc.exe with -DeterministicCompiler for public download staging.' }
    $DeterministicCompiler = (Resolve-Path -LiteralPath $DeterministicCompiler).ProviderPath
    $signature = Get-AuthenticodeSignature -LiteralPath $DeterministicCompiler
    $compilerVersion = (Get-Item -LiteralPath $DeterministicCompiler).VersionInfo
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)' -or
        $compilerVersion.OriginalFilename -ine 'csc.exe') {
        throw 'Public download staging requires a Microsoft-signed Roslyn csc.exe with a valid signature.'
    }
    & $bundleBuilder -Check
} else {
    & $bundleBuilder
}
if (!$PrepareDownload -and ($RebuildMouseHelper -or -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'OrCADWheelZoom.exe')))) {
    & (Join-Path $PSScriptRoot 'build_wheel_zoom.ps1') -DeterministicCompiler $DeterministicCompiler
}
$helperPath = Join-Path $PSScriptRoot 'OrCADWheelZoom.exe'
$expectedVersion = ([xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'OrCADWheelZoom.manifest') -Raw)).assembly.assemblyIdentity.version
$requiredFiles = $sourceNames + $documentNames
if (-not $PrepareDownload) { $requiredFiles += $runtimeNames }
foreach ($fileName in ($requiredFiles | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $fileName) -PathType Leaf)) {
        throw "Required release file missing: $fileName"
    }
}

$outputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
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

$runtimeHelper = Join-Path $runtimeRoot 'OrCADWheelZoom.exe'
if ($PrepareDownload) {
    & (Join-Path $PSScriptRoot 'build_wheel_zoom.ps1') -DeterministicCompiler $DeterministicCompiler -OutputPath $runtimeHelper
    $firstHash = (Get-FileHash -LiteralPath $runtimeHelper -Algorithm SHA256).Hash
    & (Join-Path $PSScriptRoot 'build_wheel_zoom.ps1') -DeterministicCompiler $DeterministicCompiler -OutputPath $runtimeHelper
    if ((Get-FileHash -LiteralPath $runtimeHelper -Algorithm SHA256).Hash -ne $firstHash) {
        throw 'The two deterministic helper builds have different SHA256 hashes.'
    }
} else {
    Copy-Item -LiteralPath $helperPath -Destination $runtimeHelper
}
if ((Get-Item -LiteralPath $runtimeHelper).VersionInfo.FileVersion -ne $expectedVersion) {
    throw 'The helper executable does not match the manifest version. Rebuild it first.'
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'OrCADQuickTools.tcl') -Destination $runtimeRoot
foreach ($fileName in $sourceNames) {
    $sourceDestination = Join-Path $sourceRoot $fileName
    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($sourceDestination)) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination $sourceDestination
}
foreach ($fileName in $documentNames) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $packageRoot $fileName)
}

[string[]]$paths = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | ForEach-Object {
    $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
})
[Array]::Sort($paths, [StringComparer]::Ordinal)
$hashLines = foreach ($relativeName in $paths) {
    (Get-FileHash -LiteralPath (Join-Path $packageRoot $relativeName) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relativeName
}
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllLines((Join-Path $packageRoot 'SHA256SUMS.txt'), [string[]]$hashLines, $utf8)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipDate = [DateTimeOffset]::ParseExact($releaseVersion, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
function Write-PackageZip([string]$Root, [string[]]$Entries, [string]$Archive, [string]$Prefix) {
    $zip = [IO.Compression.ZipFile]::Open($Archive, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries) {
            $entry = $zip.CreateEntry($Prefix + $name, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $zipDate
            $sourceStream = [IO.File]::OpenRead((Join-Path $Root $name))
            try {
                $entryStream = $entry.Open()
                try { $sourceStream.CopyTo($entryStream) } finally { $entryStream.Dispose() }
            } finally { $sourceStream.Dispose() }
        }
    } finally { $zip.Dispose() }
}
[string[]]$allEntries = $paths + @('SHA256SUMS.txt')
[Array]::Sort($allEntries, [StringComparer]::Ordinal)
[Array]::Sort($runtimeNames, [StringComparer]::Ordinal)
Write-PackageZip $packageRoot $allEntries $archivePath "OrCADQuickTools-$ReleaseLabel/"
Write-PackageZip $runtimeRoot $runtimeNames $runtimeArchivePath ''
$runtimeSha = (Get-FileHash -LiteralPath $runtimeArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($PrepareDownload) {
    $downloads = Join-Path $PSScriptRoot 'downloads'
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null
    $downloadName = "OrCADQuickTools-$releaseVersion-runtime.zip"
    $download = Join-Path $downloads $downloadName
    Copy-Item -LiteralPath $runtimeArchivePath -Destination $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $runtimeSha) {
        throw 'The staged download ZIP differs from the verified runtime ZIP.'
    }
    [IO.File]::WriteAllLines("$download.sha256", [string[]]@("$runtimeSha  $downloadName"), $utf8)
    $payloadHashes = foreach ($runtimeName in $runtimeNames) {
        $payloadHash = (Get-FileHash -LiteralPath (Join-Path $runtimeRoot $runtimeName) -Algorithm SHA256).Hash.ToLowerInvariant()
        "$payloadHash  $runtimeName"
    }
    [IO.File]::WriteAllLines((Join-Path $downloads "OrCADQuickTools-$releaseVersion-files.sha256"), [string[]]$payloadHashes, $utf8)
}
Write-Output ('Share package: ' + $archivePath)
Write-Output ('Two-file install ZIP: ' + $runtimeArchivePath)
Write-Output ('Runtime files: ' + $runtimeRoot)
Write-Output ('SHA256: ' + (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash)
Write-Output ('Runtime ZIP SHA256: ' + $runtimeSha)
