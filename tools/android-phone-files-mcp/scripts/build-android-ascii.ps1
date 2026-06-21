param(
    [string]$GradlePath = "D:\tools\gradle-8.10.2\bin\gradle.bat",
    [string]$BuildRoot = "$env:LOCALAPPDATA\Temp\devspace-android-build",
    [string]$OutputApk = "$PSScriptRoot\..\app\build\outputs\apk\debug\app-debug-ascii.apk"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."

if (-not (Test-Path -LiteralPath $GradlePath)) {
    throw "Gradle not found: $GradlePath"
}

Write-Host "Preparing ASCII build directory: $BuildRoot"
Remove-Item -LiteralPath $BuildRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

robocopy $ProjectRoot $BuildRoot build.gradle settings.gradle gradle.properties /NFL /NDL /NJH /NJS /NC /NS | Out-Null
robocopy (Join-Path $ProjectRoot "app") (Join-Path $BuildRoot "app") /E /XD build .gradle /NFL /NDL /NJH /NJS /NC /NS | Out-Null

Write-Host "Building APK from ASCII path..."
Push-Location $BuildRoot
try {
    & $GradlePath --no-daemon --console=plain :app:assembleDebug
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$BuiltApk = Join-Path $BuildRoot "app\build\outputs\apk\debug\app-debug.apk"
if (-not (Test-Path -LiteralPath $BuiltApk)) {
    throw "Built APK not found: $BuiltApk"
}

$Zipalign = "D:\tools\android-sdk\build-tools\35.0.0\zipalign.exe"
$ApkSigner = "D:\tools\android-sdk\build-tools\35.0.0\apksigner.bat"
if (Test-Path -LiteralPath $Zipalign) {
    $zipalignOutput = & $Zipalign -c -p -v 4 $BuiltApk
    if ($LASTEXITCODE -ne 0) {
        throw "zipalign verification failed with exit code $LASTEXITCODE"
    }
    $zipalignOutput | Select-String -Pattern "resources.arsc|Verification"
}
if (Test-Path -LiteralPath $ApkSigner) {
    & $ApkSigner verify --verbose $BuiltApk
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed with exit code $LASTEXITCODE"
    }
}

$OutputDir = Split-Path -Parent $OutputApk
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Copy-Item -LiteralPath $BuiltApk -Destination $OutputApk -Force

Get-Item -LiteralPath $OutputApk | Select-Object FullName,Length,LastWriteTime
