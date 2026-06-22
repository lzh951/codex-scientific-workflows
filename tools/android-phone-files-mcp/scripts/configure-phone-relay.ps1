param(
    [Parameter(Mandatory = $true)]
    [string]$RelayBaseUrl,

    [string]$DeviceId = "",
    [string]$AdbPath = "adb.exe",
    [int]$HostPort = 17676,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$PackageName = "com.lzh.devspaceandroid"
$ServiceComponent = "$PackageName/.PhoneMcpService"

function Invoke-Adb {
    $AdbArgs = $args
    & $AdbPath @AdbArgs
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: $($AdbArgs -join ' ')"
    }
}

function Start-PhoneService([string]$Action, [string]$RelayBaseUrl = "", [string]$DeviceId = "") {
    $serviceArgs = @("shell", "am", "start-foreground-service", "--user", "0", "-n", $ServiceComponent, "-a", $Action)
    if ($RelayBaseUrl) {
        $serviceArgs += @("--es", "relay_base_url", $RelayBaseUrl)
    }
    if ($DeviceId) {
        $serviceArgs += @("--es", "relay_device_id", $DeviceId)
    }
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        & $AdbPath @serviceArgs
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Write-Host "Service start failed, retrying ($attempt/6)..."
        Start-Sleep -Seconds 2
    }
    throw "Could not start service action: $Action"
}

function Open-PhoneApp {
    & $AdbPath shell input keyevent KEYCODE_WAKEUP | Out-Null
    Invoke-Adb shell am start --user 0 -W -n "$PackageName/.MainActivity"
    Start-Sleep -Seconds 2
}

function Invoke-HealthCheck([string]$Uri, [int]$TimeoutSec) {
    try {
        Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec | ConvertTo-Json -Compress
        return
    } catch {
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            throw
        }
        Write-Host "Invoke-RestMethod failed, retrying with curl.exe: $($_.Exception.Message)"
        & curl.exe -fsS --max-time $TimeoutSec $Uri
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed for $Uri"
        }
    }
}

function Escape-Xml([string]$Value) {
    if ($null -eq $Value) {
        return ""
    }
    return [System.Security.SecurityElement]::Escape($Value)
}

function First-Match([string]$Text, [string]$Pattern) {
    $match = [regex]::Match($Text, $Pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return $null
}

if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw "adb not found: $AdbPath"
}

$devices = & $AdbPath devices -l
$activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
if ($activeDevices.Count -eq 0) {
    throw "No ADB device is connected. Connect the phone once, enable USB debugging, then rerun this script."
}

$serial = (& $AdbPath get-serialno).Trim()
if (-not $DeviceId) {
    $DeviceId = "phone-" + ($serial -replace "[^A-Za-z0-9_.-]", "")
}

Write-Host "Opening app and starting MCP service..."
Open-PhoneApp
Start-PhoneService "$PackageName.START"
Start-Sleep -Seconds 2

Write-Host "Reading current app preferences..."
$prefs = & $AdbPath shell run-as $PackageName cat shared_prefs/devspace_android.xml 2>$null
$prefsText = $prefs -join "`n"
$existingDeviceId = First-Match $prefsText '<string name="relay_device_id">([^<]+)</string>'
if ($existingDeviceId -and -not $PSBoundParameters.ContainsKey("DeviceId")) {
    $DeviceId = $existingDeviceId
}

Write-Host "Writing phone-direct relay configuration..."
Write-Host "Relay base URL: $RelayBaseUrl"
Write-Host "Device ID: $DeviceId"
Write-Host "Existing owner/access tokens will be preserved."

Write-Host "Restarting phone-direct relay client..."
Open-PhoneApp
Start-PhoneService "$PackageName.START_RELAY" $RelayBaseUrl $DeviceId
Start-Sleep -Seconds 8

$publicHealthUrl = "$RelayBaseUrl/d/$DeviceId/healthz"
$publicMcpUrl = "$RelayBaseUrl/d/$DeviceId/mcp"

if (-not $SkipVerify) {
    Write-Host "Forwarding local test port http://127.0.0.1:$HostPort"
    try {
        & $AdbPath forward --remove "tcp:$HostPort" 2>$null | Out-Null
    } catch {
    }
    Invoke-Adb forward "tcp:$HostPort" "tcp:7676"

    Write-Host "Local phone MCP health:"
    Invoke-HealthCheck "http://127.0.0.1:$HostPort/healthz" 10

    Write-Host "Public phone-direct health: $publicHealthUrl"
    Invoke-HealthCheck $publicHealthUrl 30
}

Write-Host "Public MCP URL: $publicMcpUrl"
Write-Host "Owner token preserved in the app. Use the app's copy button only if a new authorization flow asks for it."
