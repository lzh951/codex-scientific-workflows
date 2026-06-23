param(
    [string]$TaskName = "DevSpace Android Local Temp Relay"
)

$ErrorActionPreference = "Stop"
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task removed:"
    Write-Host $TaskName
} else {
    Write-Host "Scheduled task not found:"
    Write-Host $TaskName
}

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runValue = Get-ItemProperty -Path $runKey -Name "DevSpaceAndroidLocalTempRelay" -ErrorAction SilentlyContinue
if ($runValue) {
    Remove-ItemProperty -Path $runKey -Name "DevSpaceAndroidLocalTempRelay" -Force
    Write-Host "HKCU Run autostart removed:"
    Write-Host "DevSpaceAndroidLocalTempRelay"
}
