param(
    [string]$GradlePath = "",
    [string]$BuildRoot = "$env:LOCALAPPDATA\Temp\devspace-android-build",
    [string]$OutputApk = "$PSScriptRoot\..\app\build\outputs\apk\debug\app-debug-ascii.apk"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."

if (-not $GradlePath -or -not (Test-Path -LiteralPath $GradlePath)) {
    $gradleCommand = Get-Command gradle.bat -ErrorAction SilentlyContinue
    if (-not $gradleCommand) {
        $gradleCommand = Get-Command gradle -ErrorAction SilentlyContinue
    }
    if ($gradleCommand) {
        $GradlePath = $gradleCommand.Source
    } elseif (Test-Path -LiteralPath "D:\tools\gradle-8.10.2\bin\gradle.bat") {
        $GradlePath = "D:\tools\gradle-8.10.2\bin\gradle.bat"
    } else {
        throw "Gradle not found. Pass -GradlePath or add Gradle to PATH."
    }
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

$sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "D:\tools\android-sdk") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$buildToolsDir = $null
foreach ($sdkRoot in $sdkRoots) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot "build-tools") -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($candidate) {
        $buildToolsDir = $candidate.FullName
        break
    }
}
$Zipalign = if ($buildToolsDir) { Join-Path $buildToolsDir "zipalign.exe" } else { "" }
$ApkSigner = if ($buildToolsDir) { Join-Path $buildToolsDir "apksigner.bat" } else { "" }
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
