param(
    [string]$AdbPath = "adb.exe",
    [string]$PackageName = "com.lzh.devspaceandroid"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw "adb not found: $AdbPath"
}

$devices = & $AdbPath devices -l
$activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
if ($activeDevices.Count -eq 0) {
    throw "No ADB device is connected."
}

$commands = @(
    @("shell", "pm", "grant", $PackageName, "android.permission.POST_NOTIFICATIONS"),
    @("shell", "pm", "grant", $PackageName, "android.permission.READ_MEDIA_IMAGES"),
    @("shell", "pm", "grant", $PackageName, "android.permission.READ_MEDIA_VIDEO"),
    @("shell", "pm", "grant", $PackageName, "android.permission.READ_MEDIA_AUDIO"),
    @("shell", "pm", "grant", $PackageName, "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"),
    @("shell", "pm", "grant", $PackageName, "android.permission.ACCESS_MEDIA_LOCATION"),
    @("shell", "appops", "set", "--uid", $PackageName, "MANAGE_EXTERNAL_STORAGE", "allow"),
    @("shell", "appops", "set", "--uid", $PackageName, "READ_MEDIA_IMAGES", "allow"),
    @("shell", "appops", "set", "--uid", $PackageName, "READ_MEDIA_VIDEO", "allow"),
    @("shell", "appops", "set", "--uid", $PackageName, "READ_MEDIA_AUDIO", "allow"),
    @("shell", "cmd", "deviceidle", "whitelist", "+$PackageName"),
    @("shell", "am", "set-standby-bucket", $PackageName, "active")
)

foreach ($command in $commands) {
    Write-Host "adb $($command -join ' ')"
    $output = & $AdbPath @command 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  skipped or unsupported: $output"
    } elseif ($output) {
        $output | ForEach-Object { Write-Host "  $_" }
    }
}

Write-Host "Permission summary:"
& $AdbPath shell dumpsys package $PackageName |
    Select-String -Pattern "versionName|POST_NOTIFICATIONS|READ_MEDIA_IMAGES|READ_MEDIA_VIDEO|READ_MEDIA_AUDIO|ACCESS_MEDIA_LOCATION|MANAGE_EXTERNAL_STORAGE|granted=true"

Write-Host "Device idle whitelist:"
& $AdbPath shell dumpsys deviceidle whitelist | Select-String -Pattern $PackageName

Write-Host "Standby bucket:"
& $AdbPath shell am get-standby-bucket $PackageName
