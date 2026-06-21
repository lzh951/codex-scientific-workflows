param(
    [string]$TaskName = "DevSpace Android Local Temp Relay",
    [string]$StartScript = "$PSScriptRoot\start-local-temp-relay.ps1"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $StartScript)) {
    throw "Start script not found: $StartScript"
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "Scheduled task installed:"
    Write-Host $TaskName
    Write-Host "It starts at Windows logon and reads token/device settings from runtime\local-temp-relay.env."
} catch {
    Write-Host "Scheduled task install failed: $($_.Exception.Message)"
    Write-Host "Falling back to HKCU Run autostart."
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    New-Item -Path $runKey -Force | Out-Null
    $command = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`""
    Set-ItemProperty -Path $runKey -Name "DevSpaceAndroidLocalTempRelay" -Value $command
    Write-Host "HKCU Run autostart installed:"
    Write-Host "DevSpaceAndroidLocalTempRelay"
}
