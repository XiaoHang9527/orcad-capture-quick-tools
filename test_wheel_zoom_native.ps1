$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$testDir = Join-Path $env:TEMP ('OrCADWheelNativeTests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
foreach ($platform in @('x86','x64')) {
    $testExe = Join-Path $testDir ('WheelTests-' + $platform + '.exe')
    & $compiler /nologo /target:exe "/platform:$platform" /main:WheelNativeTests /reference:System.Windows.Forms.dll /reference:Accessibility.dll "/out:$testExe" "$PSScriptRoot\OrCADWheelZoom.cs" "$PSScriptRoot\test_wheel_zoom_native.cs"
    if ($LASTEXITCODE -ne 0) {throw 'Native test compilation failed.'}
    & $testExe
    if ($LASTEXITCODE -ne 0) {throw "Native tests failed: $platform"}
}
