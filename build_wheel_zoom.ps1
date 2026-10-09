$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4 C# compiler not found.' }
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /reference:System.Windows.Forms.dll /reference:Accessibility.dll "/win32manifest:$PSScriptRoot\OrCADWheelZoom.manifest" "/out:$PSScriptRoot\OrCADWheelZoom.exe" "$PSScriptRoot\OrCADWheelZoom.cs"
if ($LASTEXITCODE -ne 0) { throw 'Wheel helper compilation failed.' }
Write-Output 'Built OrCADWheelZoom.exe'
