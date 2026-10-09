# Load the actual merged entry in an isolated folder containing only two runtimes.
[CmdletBinding()]
param([string]$Tclsh = 'C:\Cadence\Cadence_SPB_16.6\tools\tcltk\8.4\bin\tclsh.exe')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Tclsh)) { throw 'Tcl 8.4 interpreter not found; specify -Tclsh.' }
$testRoot = Join-Path $env:TEMP ('OrCADBundleTest-' + [guid]::NewGuid().ToString('N'))
$runtimeRoot = Join-Path $testRoot 'runtime'
New-Item -ItemType Directory -Path $runtimeRoot | Out-Null
foreach ($name in @('OrCADQuickTools.tcl','OrCADWheelZoom.exe')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $runtimeRoot $name)
}
if (@(Get-ChildItem -LiteralPath $runtimeRoot -File).Count -ne 2) { throw 'Expected exactly two runtime files before test.' }
# Some legacy Tcl 8.4 builds use ANSI paths. Stage the test driver outside the
# two-file runtime folder so Unicode workspace paths do not affect the test.
$testScript = Join-Path $testRoot 'test_driver.tcl'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_tcl_bundle.tcl') -Destination $testScript
$savedEntry = $env:ORCAD_BUNDLE_TEST_ENTRY
$savedWorkbook = $env:ORCAD_BUNDLE_TEST_XLSX
try {
    $env:ORCAD_BUNDLE_TEST_ENTRY = Join-Path $runtimeRoot 'OrCADQuickTools.tcl'
    $env:ORCAD_BUNDLE_TEST_XLSX = Join-Path $testRoot 'pins.xlsx'
    $testHex = ([BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($testScript))).Replace('-','')
    ('if {[catch {source [encoding convertfrom utf-8 [binary format H* ' + $testHex + ']]} err]} {puts stderr $::errorInfo; exit 1}') | & $Tclsh
    if ($LASTEXITCODE -ne 0) { throw 'Merged Tcl integration test failed.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $workbook = [System.IO.Compression.ZipFile]::OpenRead($env:ORCAD_BUNDLE_TEST_XLSX)
    try {
        if ($workbook.Entries.Count -ne 8) { throw 'Wrong XLSX package part count.' }
        foreach ($entry in $workbook.Entries) {
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
            if ($entry.FullName -eq 'xl/worksheets/sheet1.xml') { $sheet = $xml }
        }
        $namespaces = [System.Xml.XmlNamespaceManager]::new($sheet.NameTable)
        $namespaces.AddNamespace('m','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $pinNumbers = @($sheet.SelectNodes('//m:sheetData/m:row/m:c[starts-with(@r,"A")]/m:is/m:t',$namespaces) | ForEach-Object { $_.InnerText } | Where-Object { $_ -match '^\d+$' })
        if (($pinNumbers -join ',') -ne '1,2,10') { throw ('Pin order changed: ' + ($pinNumbers -join ',')) }
        if ($sheet.SelectNodes('//m:f',$namespaces).Count -ne 0) { throw 'Text property was treated as an Excel formula.' }
        if ($sheet.SelectNodes('//m:t[text()="NET<&>"]',$namespaces).Count -ne 1) { throw 'Network name XML escaping changed.' }
        if ($sheet.SelectNodes('//m:t[text()="U301"]',$namespaces).Count -ne 1) { throw 'Repeated component metadata returned.' }
    } finally { $workbook.Dispose() }
    Write-Output 'PASS: all eight XLSX XML parts parse; numeric pin order 1,2,10; names escaped; metadata shown once; no formulas.'
} finally {
    $env:ORCAD_BUNDLE_TEST_ENTRY = $savedEntry
    $env:ORCAD_BUNDLE_TEST_XLSX = $savedWorkbook
}
