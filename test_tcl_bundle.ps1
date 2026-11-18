# Load the actual merged entry in an isolated folder containing only two runtimes.
[CmdletBinding()]
param([string[]]$Tclsh)
$ErrorActionPreference = 'Stop'
if (-not $Tclsh) {
    $legacy = @(
        'C:\Cadence\Cadence_SPB_16.6\tools\tcl84\bin\tclsh84.exe',
        'C:\Cadence\Cadence_SPB_16.6\tools\tcltk\8.4\bin\tclsh.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $current = 'C:\Cadence\SPB_17.4\tcltk\bin\tclsh.exe'
    $Tclsh = @($legacy, $current | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
}
if (-not $Tclsh.Count) { throw 'No Capture Tcl interpreter found; specify -Tclsh.' }
foreach ($interpreter in $Tclsh) {
    if (-not (Test-Path -LiteralPath $interpreter -PathType Leaf)) { throw "Tcl interpreter not found: $interpreter" }
}
& (Join-Path $PSScriptRoot 'build_tcl_bundle.ps1') -Check
$tempBase = [IO.Path]::GetTempPath()
$testRoot = Join-Path $tempBase ('OrCADBundleTest-' + [guid]::NewGuid().ToString('N'))
$runtimeRoot = Join-Path $testRoot 'runtime'
$testScript = Join-Path $testRoot 'test_driver.tcl'
$savedEntry = $env:ORCAD_BUNDLE_TEST_ENTRY
$savedWorkbook = $env:ORCAD_BUNDLE_TEST_XLSX
try {
    New-Item -ItemType Directory -Path $runtimeRoot | Out-Null
    foreach ($name in @('OrCADQuickTools.tcl','OrCADWheelZoom.exe')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $runtimeRoot $name)
    }
    if (@(Get-ChildItem -LiteralPath $runtimeRoot -File).Count -ne 2) { throw 'Expected exactly two runtime files before test.' }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_tcl_bundle.tcl') -Destination $testScript
    $env:ORCAD_BUNDLE_TEST_ENTRY = Join-Path $runtimeRoot 'OrCADQuickTools.tcl'
    $testHex = ([BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($testScript))).Replace('-','')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $runNumber = 0
    foreach ($interpreter in $Tclsh) {
        $runNumber++
        $env:ORCAD_BUNDLE_TEST_XLSX = Join-Path $testRoot "pins-$runNumber.xlsx"
        $driver = 'if {[catch {source [encoding convertfrom utf-8 [binary format H* ' + $testHex + ']]} err]} {puts stderr $::errorInfo; exit 1}'
        $result = $driver | & $interpreter
        if ($LASTEXITCODE -ne 0) { throw "Merged Tcl integration test failed: $interpreter" }
        $result
        $hasZlib = [bool]($result -match '^Tcl .+; zlib=1$')
        $workbook = [IO.Compression.ZipFile]::OpenRead($env:ORCAD_BUNDLE_TEST_XLSX)
        try {
            if ($workbook.Entries.Count -ne 8) { throw 'Wrong XLSX package part count.' }
            foreach ($entry in $workbook.Entries) {
                $reader = [IO.StreamReader]::new($entry.Open())
                try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($entry.FullName -eq 'xl/worksheets/sheet1.xml') {
                    $sheet = $xml
                    if (($entry.CompressedLength -lt $entry.Length) -ne $hasZlib) {
                        throw 'The worksheet ZIP method does not match Tcl zlib availability.'
                    }
                }
                if ($entry.FullName -eq 'docProps/core.xml' -and
                    $xml.SelectSingleNode('//*[local-name()="title"]').InnerText -cne 'Test _x0041_ title') {
                    throw 'Dublin Core title text changed.'
                }
            }
            $namespaces = [Xml.XmlNamespaceManager]::new($sheet.NameTable)
            $namespaces.AddNamespace('m','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            $pinNumbers = @($sheet.SelectNodes('//m:sheetData/m:row/m:c[starts-with(@r,"A")]/m:is/m:t',$namespaces) | ForEach-Object { $_.InnerText } | Where-Object { $_ -match '^\d+$' })
            if (($pinNumbers -join ',') -ne '1,2,10') { throw ('Pin order changed: ' + ($pinNumbers -join ',')) }
            if ($sheet.SelectNodes('//m:f',$namespaces).Count -ne 0) { throw 'Text property was treated as an Excel formula.' }
            if ($sheet.SelectNodes('//m:t[text()="NET<&>"]',$namespaces).Count -ne 1) { throw 'Network name XML escaping changed.' }
            if ($sheet.SelectNodes('//m:t[text()="U301"]',$namespaces).Count -ne 1) { throw 'Repeated component metadata returned.' }
            if ($sheet.SelectNodes('//m:t[text()="Test _x005F_x0041_ title"]',$namespaces).Count -ne 1) {
                throw 'SpreadsheetML title did not escape its literal token.'
            }
        } finally { $workbook.Dispose() }
        Write-Output 'PASS: all eight XLSX XML parts parse; compression, titles and pin ordering verified.'
    }
} finally {
    $env:ORCAD_BUNDLE_TEST_ENTRY = $savedEntry
    $env:ORCAD_BUNDLE_TEST_XLSX = $savedWorkbook
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = (Resolve-Path -LiteralPath $testRoot).ProviderPath
        $tempPrefix = (Resolve-Path -LiteralPath $tempBase).ProviderPath.TrimEnd('\') + '\'
        if ($resolvedRoot.StartsWith($tempPrefix + 'OrCADBundleTest-', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse
        }
    }
}
