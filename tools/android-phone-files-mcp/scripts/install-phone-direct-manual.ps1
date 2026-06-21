param(
    [string]$AdbPath = "adb.exe",
    [string]$ApkPath = "$PSScriptRoot\..\app\build\outputs\apk\debug\app-debug-ascii.apk",
    [string]$RelayBaseUrl = "",
    [string]$DeviceId = "",
    [string]$ConfigPath = "$PSScriptRoot\..\runtime\local-temp-relay.env",
    [int]$HostPort = 17676,
    [int]$WaitForDeviceSeconds = 0
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

function Read-EnvFile([string]$Path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        $index = $trimmed.IndexOf("=")
        if ($index -lt 1) {
            continue
        }
        $key = $trimmed.Substring(0, $index).Trim()
        $value = $trimmed.Substring($index + 1).Trim()
        $values[$key] = $value
    }
    return $values
}

function Wait-AdbDevice([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $Seconds))
    do {
        $devices = & $AdbPath devices -l
        $activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
        if ($activeDevices.Count -gt 0) {
            return $true
        }
        if ($Seconds -le 0) {
            return $false
        }
        Write-Host "Waiting for ADB device..."
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Start-PhoneService([string]$Action) {
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        & $AdbPath shell am start-foreground-service --user 0 -n $ServiceComponent -a $Action
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

if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw "adb not found: $AdbPath"
}
if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK not found: $ApkPath"
}

$config = Read-EnvFile $ConfigPath
if (-not $PSBoundParameters.ContainsKey("RelayBaseUrl") -and $config["RELAY_BASE_URL"]) {
    $RelayBaseUrl = $config["RELAY_BASE_URL"]
}
if (-not $PSBoundParameters.ContainsKey("DeviceId") -and $config["DEVICE_ID"]) {
    $DeviceId = $config["DEVICE_ID"]
}
if (-not $RelayBaseUrl) {
    $RelayBaseUrl = "https://example.trycloudflare.com"
}

if (-not (Wait-AdbDevice $WaitForDeviceSeconds)) {
    throw "No ADB device is connected. Reconnect the phone, enable USB debugging, then rerun this script. To wait automatically, rerun with -WaitForDeviceSeconds 300."
}

$serial = (& $AdbPath get-serialno).Trim()
if (-not $DeviceId) {
    $DeviceId = "phone-" + ($serial -replace "[^A-Za-z0-9_.-]", "")
}

Write-Host "Installing APK: $ApkPath"
Invoke-Adb install -r $ApkPath
Start-Sleep -Seconds 3

Write-Host "Granting phone-direct permissions and power allowances..."
$grantScript = Join-Path $PSScriptRoot "grant-phone-direct-permissions.ps1"
if (Test-Path -LiteralPath $grantScript) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $grantScript -AdbPath $AdbPath -PackageName $PackageName
}

Write-Host "Opening app and starting MCP service..."
Invoke-Adb shell am force-stop $PackageName
Open-PhoneApp
Start-PhoneService "$PackageName.START"
Start-Sleep -Seconds 3

Write-Host "Reading owner token from app private preferences..."
$prefs = & $AdbPath shell run-as $PackageName cat shared_prefs/devspace_android.xml 2>$null
$ownerToken = $null
$ownerTokenMatch = [regex]::Match(($prefs -join "`n"), '<string name="owner_token">([^<]+)</string>')
if ($ownerTokenMatch.Success) {
    $ownerToken = $ownerTokenMatch.Groups[1].Value
}
if (-not $ownerToken) {
    throw "Could not read owner token from app preferences."
}

Write-Host "Writing relay configuration: $RelayBaseUrl / $DeviceId"
$xml = @"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="owner_token">$(Escape-Xml $ownerToken)</string>
    <string name="relay_base_url">$(Escape-Xml $RelayBaseUrl)</string>
    <string name="relay_device_id">$(Escape-Xml $DeviceId)</string>
</map>
"@
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "devspace-prefs.xml"
[System.IO.File]::WriteAllText($temp, $xml, [System.Text.UTF8Encoding]::new($false))
Invoke-Adb push $temp /data/local/tmp/devspace-prefs.xml
Invoke-Adb shell "run-as $PackageName sh -c 'mkdir -p shared_prefs && cp /data/local/tmp/devspace-prefs.xml shared_prefs/devspace_android.xml && chmod 660 shared_prefs/devspace_android.xml'"

Write-Host "Restarting phone-direct relay client..."
Invoke-Adb shell am force-stop $PackageName
Open-PhoneApp
Start-PhoneService "$PackageName.START_RELAY"
Start-Sleep -Seconds 8

Write-Host "Forwarding local test port http://127.0.0.1:$HostPort"
try {
    & $AdbPath forward --remove "tcp:$HostPort" 2>$null | Out-Null
} catch {
}
Invoke-Adb forward "tcp:$HostPort" "tcp:7676"

Write-Host "Local phone MCP health:"
Invoke-HealthCheck "http://127.0.0.1:$HostPort/healthz" 10

Write-Host "Local phone relay status:"
Invoke-RestMethod -Uri "http://127.0.0.1:$HostPort/relay_status" -TimeoutSec 10 | ConvertTo-Json -Compress

$publicHealthUrl = "$RelayBaseUrl/d/$DeviceId/healthz"
$publicMcpUrl = "$RelayBaseUrl/d/$DeviceId/mcp"
Write-Host "Public phone-direct health: $publicHealthUrl"
Invoke-HealthCheck $publicHealthUrl 30

Write-Host "Public MCP URL: $publicMcpUrl"
Write-Host "Owner token: $ownerToken"
