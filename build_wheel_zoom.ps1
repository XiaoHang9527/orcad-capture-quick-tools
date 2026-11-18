[CmdletBinding()]
param([string]$DeterministicCompiler, [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
$compiler = Join-Path $framework 'csc.exe'
if ($DeterministicCompiler) { $compiler = (Resolve-Path -LiteralPath $DeterministicCompiler).ProviderPath }
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'C# compiler not found.' }
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'OrCADWheelZoom.exe' }
$manifest = Join-Path $PSScriptRoot 'OrCADWheelZoom.manifest'
$version = ([xml](Get-Content -LiteralPath $manifest -Raw)).assembly.assemblyIdentity.version
$null = [version]$version
$versionDir = Join-Path $env:TEMP ('OrCADWheelVersion-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $versionDir)
$versionSource = Join-Path $versionDir 'Version.cs'
try {
    @(
        '[assembly: System.Reflection.AssemblyVersion("' + $version + '")]'
        '[assembly: System.Reflection.AssemblyFileVersion("' + $version + '")]'
    ) | Set-Content -LiteralPath $versionSource -Encoding Ascii
    $flags = @('/nologo', '/noconfig', '/target:winexe', '/platform:anycpu', '/optimize+', '/debug-', '/nostdlib+')
    foreach ($assembly in @('mscorlib', 'System', 'System.Core', 'System.Drawing', 'System.Windows.Forms', 'Accessibility')) {
        $flags += '/reference:' + (Join-Path $framework ($assembly + '.dll'))
    }
    if ($DeterministicCompiler) {
        $flags += '/deterministic+', "/pathmap:$versionDir=/_version,$PSScriptRoot=/_src"
    }
    & $compiler @flags "/win32manifest:$manifest" "/out:$OutputPath" "$PSScriptRoot\OrCADWheelZoom.cs" $versionSource
    if ($LASTEXITCODE -ne 0) { throw 'Wheel helper compilation failed.' }
    Write-Output ('Built wheel helper ' + $version + ': ' + $OutputPath)
} finally {
    Remove-Item -LiteralPath $versionSource -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $versionDir -ErrorAction SilentlyContinue
}
