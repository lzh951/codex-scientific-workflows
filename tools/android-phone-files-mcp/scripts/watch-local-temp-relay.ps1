param(
    [string]$ProjectRoot = "$PSScriptRoot\..",
    [int]$IntervalSeconds = 60,
    [int]$RelayPort = 8788,
    [string]$DeviceId = "phone-example",
    [string]$AdbPath = "adb.exe",
    [int]$HostPort = 17676,
    [string]$LogPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$RuntimeDir = Join-Path $ProjectRoot "runtime"
$StartScript = Join-Path $ProjectRoot "scripts\start-local-temp-relay.ps1"
$ConfigurePhoneScript = Join-Path $ProjectRoot "scripts\configure-phone-relay.ps1"
$CloudflaredLog = Join-Path $RuntimeDir "local-relay-cloudflared.log"
$CurrentUrlFile = Join-Path $RuntimeDir "local-temp-relay-current-url.txt"
if (-not $LogPath) {
    $LogPath = Join-Path $RuntimeDir "local-temp-relay-watch.log"
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

$mutex = New-Object System.Threading.Mutex($false, "Global\DevSpaceAndroidLocalTempRelayWatch")
if (-not $mutex.WaitOne(0)) {
    Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) Another watcher is already running. Exiting."
    exit 0
}

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message"
}

function Test-HttpOk([string]$Url, [int]$TimeoutSeconds) {
    try {
        Invoke-RestMethod -Uri $Url -TimeoutSec $TimeoutSeconds | Out-Null
        return $true
    } catch {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fsS --max-time $TimeoutSeconds $Url *> $null
            return $LASTEXITCODE -eq 0
        }
        return $false
    }
}

function Get-TryCloudflareUrl {
    if (-not (Test-Path -LiteralPath $CloudflaredLog)) {
        return Get-PhoneOrSavedTryCloudflareUrl
    }
    $text = Get-Content -LiteralPath $CloudflaredLog -Raw -ErrorAction SilentlyContinue
    $matches = [regex]::Matches($text, 'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
    if ($matches.Count -eq 0) {
        return Get-PhoneOrSavedTryCloudflareUrl
    }
    $url = $matches[$matches.Count - 1].Value
    Set-Content -LiteralPath $CurrentUrlFile -Value $url -NoNewline
    return $url
}

function Get-PhoneOrSavedTryCloudflareUrl {
    $phoneUrl = Get-PhoneRelayBaseUrl
    if ($phoneUrl -match '^https://[a-zA-Z0-9-]+\.trycloudflare\.com$') {
        Set-Content -LiteralPath $CurrentUrlFile -Value $phoneUrl -NoNewline
        return $phoneUrl
    }
    if (Test-Path -LiteralPath $CurrentUrlFile) {
        $saved = (Get-Content -LiteralPath $CurrentUrlFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($saved -match '^https://[a-zA-Z0-9-]+\.trycloudflare\.com$') {
            return $saved
        }
    }
    return ""
}

function Get-PhoneRelayBaseUrl {
    if (-not (Test-Path -LiteralPath $AdbPath)) {
        return ""
    }
    try {
        $devices = & $AdbPath devices -l
        $activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
        if ($activeDevices.Count -eq 0) {
            return ""
        }
        & $AdbPath forward --remove "tcp:$HostPort" 2>$null | Out-Null
        & $AdbPath forward "tcp:$HostPort" "tcp:7676" | Out-Null
        $status = Invoke-RestMethod -Uri "http://127.0.0.1:$HostPort/relay_status" -TimeoutSec 8
        if ($status -and $status.relayBaseUrl) {
            return ([string]$status.relayBaseUrl).TrimEnd("/")
        }
        return ""
    } catch {
        return ""
    }
}

function Restart-Relay([string]$Reason) {
    Write-Log "Restarting local temp relay: $Reason"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $StartScript -ReplacePortOwner *>&1 |
        ForEach-Object { Write-Log "  $_" }
}

function Test-AdbDevice {
    if (-not (Test-Path -LiteralPath $AdbPath)) {
        return $false
    }
    try {
        $devices = & $AdbPath devices -l
        $activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
        return $activeDevices.Count -gt 0
    } catch {
        return $false
    }
}

function Configure-PhoneRelay([string]$RelayBaseUrl) {
    if (-not (Test-Path -LiteralPath $ConfigurePhoneScript)) {
        Write-Log "Phone configure skipped; script missing: $ConfigurePhoneScript"
        return
    }
    Write-Log "Configuring phone relay for $RelayBaseUrl"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ConfigurePhoneScript -RelayBaseUrl $RelayBaseUrl -DeviceId $DeviceId -AdbPath $AdbPath -HostPort $HostPort *>&1 |
        ForEach-Object { Write-Log "  $_" }
}

try {
    Write-Log "Watcher started. ProjectRoot=$ProjectRoot IntervalSeconds=$IntervalSeconds RelayPort=$RelayPort DeviceId=$DeviceId"
    $publicFailureCount = 0
    $missingUrlLoggedAt = [datetime]::MinValue
    $phoneDisconnectedLoggedAt = [datetime]::MinValue
    $lastPhoneConfigureAttemptAt = [datetime]::MinValue
    while ($true) {
        $localUrl = "http://127.0.0.1:$RelayPort/healthz"
        if (-not (Test-HttpOk $localUrl 5)) {
            $publicFailureCount = 0
            Restart-Relay "local relay health failed at $localUrl"
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $publicUrl = Get-TryCloudflareUrl
        if (-not $publicUrl) {
            if (((Get-Date) - $missingUrlLoggedAt).TotalMinutes -ge 10) {
                Write-Log "No trycloudflare URL found in $CloudflaredLog; skipping public tunnel check while local relay is healthy."
                $missingUrlLoggedAt = Get-Date
            }
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        if (-not (Test-HttpOk "$publicUrl/healthz" 10)) {
            $publicFailureCount++
            Write-Log "Public tunnel health failed ($publicFailureCount/2) at $publicUrl/healthz"
            if ($publicFailureCount -ge 2) {
                $publicFailureCount = 0
                Restart-Relay "public tunnel health failed twice at $publicUrl/healthz"
            }
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $publicFailureCount = 0

        $phoneHealthUrl = "$publicUrl/d/$DeviceId/healthz"
        if (-not (Test-HttpOk $phoneHealthUrl 10)) {
            if (Test-AdbDevice) {
                if (((Get-Date) - $lastPhoneConfigureAttemptAt).TotalSeconds -ge [Math]::Max(30, $IntervalSeconds)) {
                    $lastPhoneConfigureAttemptAt = Get-Date
                    Configure-PhoneRelay $publicUrl
                }
            } elseif (((Get-Date) - $phoneDisconnectedLoggedAt).TotalMinutes -ge 10) {
                Write-Log "Phone is not connected to relay and no ADB device is available: $phoneHealthUrl"
                $phoneDisconnectedLoggedAt = Get-Date
            }
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
}
