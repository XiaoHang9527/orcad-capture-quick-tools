# Assemble readable Tcl modules into one Capture autoload entry.
[CmdletBinding()]
param([switch]$Check, [switch]$ListModules, [switch]$PrintVersion)
$ErrorActionPreference = 'Stop'
$releaseVersion = '2026.11.18'
if ($PrintVersion) { $releaseVersion; return }
$modules = @(
    @{ File = 'OrCADQuickTools.core.tcl'; Title = '01 CORE / ACTION REGISTRY / EDITING OPERATIONS / HELP' },
    @{ File = 'OrCADPinNetXlsx.tcl'; Title = '02 EMBEDDED XLSX WRITER (NO EXCEL DEPENDENCY)' },
    @{ File = 'OrCADOffPageToggle.tcl'; Title = '03 OFF-PAGE INPUT/OUTPUT GRAPHIC TOGGLE' },
    @{ File = 'OrCADWheelZoom.tcl'; Title = '04 MOUSE NAVIGATION CONTROLLER' },
    @{ File = 'OrCADPartPreview.tcl'; Title = '05 READ-ONLY PART CLICK PREVIEW / CONFIGURABLE FIELDS' },
    @{ File = 'OrCADDesignPinNetExport.tcl'; Title = '06 ALL-DESIGN PIN-NET EXPORT' }
)
if ($ListModules) { $modules | ForEach-Object { 'src/' + $_.File }; return }
$manifestPath = Join-Path $PSScriptRoot 'OrCADWheelZoom.manifest'
$helperVersion = ([version]([xml](Get-Content -LiteralPath $manifestPath -Raw)).assembly.assemblyIdentity.version).ToString(2)
$bundle = [System.Text.StringBuilder]::new()
[void]$bundle.AppendLine("# OrCAD Capture Quick Tools - $releaseVersion / merged two-file edition / helper $helperVersion")
[void]$bundle.AppendLine('# Runtime: OrCADQuickTools.tcl + OrCADWheelZoom.exe in the same directory.')
[void]$bundle.AppendLine('# Tcl 8.4; ASCII source / Unicode-escaped UI; no external Tcl source calls.')
[void]$bundle.AppendLine('#')
[void]$bundle.AppendLine('# MODULE INDEX:')
foreach ($module in $modules) { [void]$bundle.AppendLine('#   ' + $module.Title) }
[void]$bundle.AppendLine('#   07 INITIALIZATION (runs only after all modules are defined)')
[void]$bundle.AppendLine('#')
[void]$bundle.AppendLine('# EXTENDING: implement a namespaced command and add one six-field record')
[void]$bundle.AppendLine('# to ::OrCADQuickTools::ActionDefinitions near the top of module 01.')
[void]$bundle.AppendLine('# Registration, menu and help share that registry. Duplicate keys are rejected.')
[void]$bundle.AppendLine('# Prefer editing src modules and rebuilding with build_tcl_bundle.ps1.')
[void]$bundle.AppendLine('# If editing this published file directly, sync edits into src before rebuilding.')
[void]$bundle.AppendLine('')

foreach ($module in $modules) {
    $sourcePath = Join-Path (Join-Path $PSScriptRoot 'src') $module.File
    $bytes = [System.IO.File]::ReadAllBytes($sourcePath)
    foreach ($byte in $bytes) { if ($byte -gt 127) { throw ('Non-ASCII module: ' + $module.File) } }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes).Replace("`r`n", "`n")
    if ($text -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]') {
        throw ('Unexpected control characters in module: ' + $module.File)
    }
    [void]$bundle.AppendLine('# ============================================================================')
    [void]$bundle.AppendLine('# BEGIN MODULE: ' + $module.Title)
    [void]$bundle.AppendLine('# Development source: src/' + $module.File)
    [void]$bundle.AppendLine('# ============================================================================')
    [void]$bundle.AppendLine($text.TrimEnd())
    [void]$bundle.AppendLine('# END MODULE: ' + $module.Title)
    [void]$bundle.AppendLine('')
}
[void]$bundle.AppendLine('# ============================================================================')
[void]$bundle.AppendLine('# 07 INITIALIZATION - keep this after ALL module definitions.')
[void]$bundle.AppendLine('# ============================================================================')
[void]$bundle.AppendLine('::OrCADQuickTools::Initialize')
$outputPath = Join-Path $PSScriptRoot 'OrCADQuickTools.tcl'
$result = $bundle.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")
if ($Check) {
    $actual = [System.IO.File]::ReadAllBytes($outputPath)
    $expected = [System.Text.Encoding]::ASCII.GetBytes($result)
    if ([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($expected)) {
        throw 'Runtime Tcl differs from the source modules. Run build_tcl_bundle.ps1.'
    }
    Write-Output 'PASS: source modules reproduce the runtime Tcl byte for byte.'
    return
}
[System.IO.File]::WriteAllText($outputPath, $result, [System.Text.Encoding]::ASCII)
Write-Output ('Built merged Tcl: ' + $outputPath)
