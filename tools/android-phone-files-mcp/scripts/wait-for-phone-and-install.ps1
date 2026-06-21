param(
    [string]$AdbPath = "adb.exe",
    [int]$WaitForDeviceSeconds = 1800,
    [int]$HostPort = 17676,
    [switch]$StartRelayIfNeeded,
    [string]$LogPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$RuntimeDir = Join-Path $ProjectRoot "runtime"
$InstallScript = Join-Path $PSScriptRoot "install-phone-direct-manual.ps1"
$StartRelayScript = Join-Path $PSScriptRoot "start-local-temp-relay.ps1"
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
if (-not $LogPath) {
    $LogPath = Join-Path $RuntimeDir "wait-install-phone-direct.log"
}

function Write-Log([string]$Message) {
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line
}

function Test-HttpOk([string]$Url) {
    try {
        Invoke-RestMethod -Uri $Url -TimeoutSec 5 | Out-Null
        return $true
    } catch {
        return $false
    }
}

Write-Log "Starting wait-for-phone install workflow."
Write-Log "Project root: $ProjectRoot"
Write-Log "ADB path: $AdbPath"
Write-Log "Wait seconds: $WaitForDeviceSeconds"

if ($StartRelayIfNeeded -and -not (Test-HttpOk "http://127.0.0.1:8788/healthz")) {
    Write-Log "Local relay is not healthy; starting local temp relay."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $StartRelayScript -ReplacePortOwner *>&1 |
        Tee-Object -FilePath $LogPath -Append
}

Write-Log "Waiting for phone and installing current APK."
& powershell -NoProfile -ExecutionPolicy Bypass -File $InstallScript `
    -AdbPath $AdbPath `
    -WaitForDeviceSeconds $WaitForDeviceSeconds `
    -HostPort $HostPort *>&1 |
    Tee-Object -FilePath $LogPath -Append

if ($LASTEXITCODE -ne 0) {
    throw "install-phone-direct-manual.ps1 failed with exit code $LASTEXITCODE. See log: $LogPath"
}

Write-Log "Phone install workflow completed."
