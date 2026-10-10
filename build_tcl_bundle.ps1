# Assemble readable Tcl modules into one Capture autoload entry.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$modules = @(
    @{ File = 'OrCADQuickTools.core.tcl'; Title = '01 CORE / ACTION REGISTRY / EDITING OPERATIONS / HELP' },
    @{ File = 'OrCADPinNetXlsx.tcl'; Title = '02 EMBEDDED XLSX WRITER (NO EXCEL DEPENDENCY)' },
    @{ File = 'OrCADOffPageToggle.tcl'; Title = '03 OFF-PAGE INPUT/OUTPUT GRAPHIC TOGGLE' },
    @{ File = 'OrCADWheelZoom.tcl'; Title = '04 MOUSE NAVIGATION CONTROLLER' }
)
$bundle = [System.Text.StringBuilder]::new()
[void]$bundle.AppendLine('# OrCAD Capture Quick Tools - merged two-file edition, 2026.10.10 / helper 0.20')
[void]$bundle.AppendLine('# Runtime: OrCADQuickTools.tcl + OrCADWheelZoom.exe in the same directory.')
[void]$bundle.AppendLine('# Tcl 8.4; ASCII source / Unicode-escaped UI; no external Tcl source calls.')
[void]$bundle.AppendLine('#')
[void]$bundle.AppendLine('# MODULE INDEX:')
foreach ($module in $modules) { [void]$bundle.AppendLine('#   ' + $module.Title) }
[void]$bundle.AppendLine('#   05 INITIALIZATION (runs only after all modules are defined)')
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
    # The legacy writer contains literal regex control characters. Emit the
    # equivalent Unicode regex escapes so the merged source stays plain text.
    $text = [regex]::Replace($text, '[\x00-\x08\x0b\x0c\x0e-\x1f]', {
        param($controlMatch)
        '\u{0:x4}' -f [int][char]$controlMatch.Value
    })
    [void]$bundle.AppendLine('# ============================================================================')
    [void]$bundle.AppendLine('# BEGIN MODULE: ' + $module.Title)
    [void]$bundle.AppendLine('# Development source: src/' + $module.File)
    [void]$bundle.AppendLine('# ============================================================================')
    [void]$bundle.AppendLine($text.TrimEnd())
    [void]$bundle.AppendLine('# END MODULE: ' + $module.Title)
    [void]$bundle.AppendLine('')
}
[void]$bundle.AppendLine('# ============================================================================')
[void]$bundle.AppendLine('# 05 INITIALIZATION - keep this after ALL module definitions.')
[void]$bundle.AppendLine('# ============================================================================')
[void]$bundle.AppendLine('::OrCADQuickTools::Initialize')
$outputPath = Join-Path $PSScriptRoot 'OrCADQuickTools.tcl'
$result = $bundle.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")
[System.IO.File]::WriteAllText($outputPath, $result, [System.Text.Encoding]::ASCII)
Write-Output ('Built merged Tcl: ' + $outputPath)
