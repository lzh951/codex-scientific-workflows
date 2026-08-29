Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Section($Name) {
    ""
    "## $Name"
}

Section "Origin-related processes"
Get-Process |
    Where-Object {
        ($_.ProcessName -match "Origin|Origin64") -or
        ($_.MainWindowTitle -match "Origin") -or
        ($_.Path -match "OriginLab")
    } |
    Select-Object ProcessName, Id, MainWindowTitle, Path |
    Format-Table -AutoSize

Section "Installed Origin executables"
$candidatePaths = @(
    "$env:ProgramFiles\OriginLab\Origin2026\Origin64.exe",
    "$env:ProgramFiles\OriginLab\Origin2025b\Origin64.exe",
    "$env:ProgramFiles\OriginLab\Origin2025\Origin64.exe",
    "${env:ProgramFiles(x86)}\OriginLab\Origin2026\Origin64.exe",
    "${env:ProgramFiles(x86)}\OriginLab\Origin2025b\Origin64.exe",
    "${env:ProgramFiles(x86)}\OriginLab\Origin2025\Origin64.exe"
)
foreach ($path in $candidatePaths) {
    if (Test-Path -LiteralPath $path) {
        Get-Item -LiteralPath $path | Select-Object FullName, Length, LastWriteTime
    }
}

Section "OriginLab install directories"
Get-ChildItem -LiteralPath "$env:ProgramFiles\OriginLab" -Directory |
    Select-Object FullName, LastWriteTime

Section "Python originpro availability"
python -c "import originpro, sys; print('originpro import ok:', getattr(originpro, '__version__', 'unknown'))"
