param(
    [string]$AdbPath = "adb.exe",
    [string]$ApkPath = "$PSScriptRoot\..\app\build\outputs\apk\debug\app-debug.apk",
    [int]$HostPort = 17676,
    [string]$RelayBaseUrl = ""
)

$ErrorActionPreference = "Stop"

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $AdbPath @Args
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: $($Args -join ' ')"
    }
}

function Grant-PermissionIfPossible {
    param([string]$Permission)
    $output = & $AdbPath shell pm grant com.lzh.devspaceandroid $Permission 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Permission not granted by pm grant: $Permission ($output)"
    }
}

function Set-AppOpIfPossible {
    param(
        [string]$Op,
        [string]$Mode = "allow"
    )
    $output = & $AdbPath shell appops set com.lzh.devspaceandroid $Op $Mode 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "AppOp not set: $Op ($output)"
    }
}

function Get-ButtonCenter {
    param(
        [string]$XmlPath,
        [string]$Text
    )
    $xmlText = Get-Content -LiteralPath $XmlPath -Raw
    $pattern = 'text="' + [regex]::Escape($Text) + '".*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $match = [regex]::Match($xmlText, $pattern)
    if (-not $match.Success) {
        throw "Could not find button: $Text"
    }
    $x1 = [int]$match.Groups[1].Value
    $y1 = [int]$match.Groups[2].Value
    $x2 = [int]$match.Groups[3].Value
    $y2 = [int]$match.Groups[4].Value
    return @([int](($x1 + $x2) / 2), [int](($y1 + $y2) / 2))
}

if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw "adb not found: $AdbPath"
}
if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK not found: $ApkPath"
}

Write-Host "Connected devices:"
Invoke-Adb devices -l

Write-Host "Allowing Xiaomi/HyperOS USB install source when available..."
& $AdbPath shell settings put secure com.miui.packageinstaller_install_not_allow_package_com.android.shell '{\"allowInstall\":true}' | Out-Null

Write-Host "Installing APK: $ApkPath"
Invoke-Adb install -r $ApkPath

Write-Host "Granting file and notification permissions..."
Set-AppOpIfPossible MANAGE_EXTERNAL_STORAGE
Set-AppOpIfPossible READ_MEDIA_IMAGES
Set-AppOpIfPossible READ_MEDIA_VIDEO
Set-AppOpIfPossible READ_MEDIA_AUDIO
Set-AppOpIfPossible ACCESS_MEDIA_LOCATION
Set-AppOpIfPossible READ_EXTERNAL_STORAGE
Set-AppOpIfPossible WRITE_EXTERNAL_STORAGE
Grant-PermissionIfPossible android.permission.POST_NOTIFICATIONS
Grant-PermissionIfPossible android.permission.READ_MEDIA_IMAGES
Grant-PermissionIfPossible android.permission.READ_MEDIA_VIDEO
Grant-PermissionIfPossible android.permission.READ_MEDIA_AUDIO
Grant-PermissionIfPossible android.permission.ACCESS_MEDIA_LOCATION
Grant-PermissionIfPossible android.permission.READ_EXTERNAL_STORAGE
Grant-PermissionIfPossible android.permission.WRITE_EXTERNAL_STORAGE

Write-Host "Opening app..."
Invoke-Adb shell am start -n com.lzh.devspaceandroid/.MainActivity
& $AdbPath shell monkey -p com.lzh.devspaceandroid -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "Starting foreground MCP service..."
$serviceOutput = & $AdbPath shell am start-foreground-service -n com.lzh.devspaceandroid/.PhoneMcpService -a com.lzh.devspaceandroid.START 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Direct service start failed; falling back to UI tap. $serviceOutput"
    $uiOnDevice = "/sdcard/devspace-install-start-ui.xml"
    $uiLocal = Join-Path $PSScriptRoot "devspace-install-start-ui.xml"
    Invoke-Adb shell uiautomator dump $uiOnDevice
    Invoke-Adb pull $uiOnDevice $uiLocal
    $center = Get-ButtonCenter -XmlPath $uiLocal -Text "Start MCP server"
    Write-Host "Tapping Start MCP server at $($center[0]),$($center[1])"
    Invoke-Adb shell input tap $center[0] $center[1]
}
Start-Sleep -Seconds 2

if ($RelayBaseUrl) {
    Write-Host "Saving relay URL and starting phone-direct tunnel: $RelayBaseUrl"
    $relayOutput = & $AdbPath shell am start-foreground-service -n com.lzh.devspaceandroid/.PhoneMcpService -a com.lzh.devspaceandroid.START_RELAY --es relay_base_url "$RelayBaseUrl" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not start relay service: $relayOutput"
    }
    Start-Sleep -Seconds 3
}

Write-Host "Forwarding http://127.0.0.1:$HostPort to phone port 7676"
try {
    & $AdbPath forward --remove "tcp:$HostPort" 2>$null | Out-Null
} catch {
    Write-Host "No existing tcp:$HostPort forward to remove."
}
Invoke-Adb forward "tcp:$HostPort" "tcp:7676"

Write-Host "Checking health endpoint..."
$health = Invoke-RestMethod -Uri "http://127.0.0.1:$HostPort/healthz"
$health | ConvertTo-Json -Compress
Write-Host "Phone MCP local test URL: http://127.0.0.1:$HostPort/mcp"
