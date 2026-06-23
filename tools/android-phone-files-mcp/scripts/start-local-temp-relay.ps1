param(
    [string]$NodePath = "",
    [string]$CloudflaredPath = "",
    [string]$DeviceId = "phone-example",
    [string]$OwnerToken = "",
    [string]$ConfigPath = "",
    [string]$AdbPath = "",
    [switch]$ConfigurePhone,
    [int]$RelayPort = 8788,
    [switch]$ReplacePortOwner,
    [switch]$NoTunnel
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$RelayDir = Join-Path $ProjectRoot "relay\node-relay"
$RuntimeDir = Join-Path $ProjectRoot "runtime"
if (-not $CloudflaredPath) {
    $CloudflaredPath = Join-Path $ProjectRoot "tools\cloudflared.exe"
}
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $RuntimeDir "local-temp-relay.env"
}
if (-not $AdbPath) {
    $AdbPath = "adb.exe"
}
$NodePidFile = Join-Path $RuntimeDir "local-relay-node.pid"
$CloudflaredPidFile = Join-Path $RuntimeDir "local-relay-cloudflared.pid"
$CloudflaredLog = Join-Path $RuntimeDir "local-relay-cloudflared.log"
$PhoneConfigureLog = Join-Path $RuntimeDir "local-relay-phone-configure.log"

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

function Stop-FromPidFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $pidText = (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Select-Object -First 1)
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $pidText) {
        return
    }
    $process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $process.Id -Force
    }
}

function Wait-HttpOk([string]$Url, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            Invoke-RestMethod -Uri $Url -TimeoutSec 3 | Out-Null
            return $true
        } catch {
            Start-Sleep -Milliseconds 500
        }
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Read-TryCloudflareUrl {
    if (-not (Test-Path -LiteralPath $CloudflaredLog)) {
        return ""
    }
    $text = Get-Content -LiteralPath $CloudflaredLog -Raw -ErrorAction SilentlyContinue
    $match = [regex]::Match($text, 'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
    if ($match.Success) {
        return $match.Value
    }
    return ""
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

$config = Read-EnvFile $ConfigPath
if (-not $PSBoundParameters.ContainsKey("DeviceId") -and $config["DEVICE_ID"]) {
    $DeviceId = $config["DEVICE_ID"]
}
if (-not $OwnerToken -and $config["OWNER_TOKEN"]) {
    $OwnerToken = $config["OWNER_TOKEN"]
}
if (-not $PSBoundParameters.ContainsKey("RelayPort") -and $config["RELAY_PORT"]) {
    $RelayPort = [int]$config["RELAY_PORT"]
}
if (-not $PSBoundParameters.ContainsKey("CloudflaredPath") -and $config["CLOUDFLARED_PATH"]) {
    $CloudflaredPath = $config["CLOUDFLARED_PATH"]
}
if (-not $PSBoundParameters.ContainsKey("AdbPath") -and $config["ADB_PATH"]) {
    $AdbPath = $config["ADB_PATH"]
}
if (-not $ConfigurePhone -and $config["AUTO_CONFIGURE_PHONE"] -and $config["AUTO_CONFIGURE_PHONE"].ToLowerInvariant() -in @("1", "true", "yes", "on")) {
    $ConfigurePhone = $true
}

Stop-FromPidFile $CloudflaredPidFile
Stop-FromPidFile $NodePidFile

$existingListeners = @(Get-NetTCPConnection -LocalPort $RelayPort -State Listen -ErrorAction SilentlyContinue)
if ($existingListeners.Count -gt 0) {
    if (-not $ReplacePortOwner) {
        $owners = ($existingListeners | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique) -join ", "
        throw "Port $RelayPort is already listening. Owning process id(s): $owners. Use status-local-temp-relay.ps1 to inspect, or rerun with -ReplacePortOwner if this is the old local relay."
    }
    foreach ($listener in $existingListeners) {
        $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -eq "node") {
            Stop-Process -Id $process.Id -Force
            Write-Host "Stopped node process owning port ${RelayPort}: PID $($process.Id)"
        } else {
            throw "Port $RelayPort is owned by PID $($listener.OwningProcess), not a node process. Refusing to replace it."
        }
    }
    Start-Sleep -Seconds 2
}

if (-not $NodePath) {
    $nodeCommand = Get-Command node.exe -ErrorAction Stop
    $NodePath = $nodeCommand.Source
}
if (-not (Test-Path -LiteralPath $NodePath)) {
    throw "node.exe not found: $NodePath"
}
if (-not (Test-Path -LiteralPath (Join-Path $RelayDir "server.js"))) {
    throw "Node relay server.js not found under: $RelayDir"
}

$env:PORT = [string]$RelayPort
$env:PHONE_DEVICE_ID = $DeviceId
if ($OwnerToken) {
    $env:PHONE_OWNER_TOKEN = $OwnerToken
}
try {
    $nodeProcess = Start-Process -FilePath $NodePath -ArgumentList "server.js" -WorkingDirectory $RelayDir -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $NodePidFile -Value $nodeProcess.Id -NoNewline
} finally {
    Remove-Item Env:\PORT -ErrorAction SilentlyContinue
    Remove-Item Env:\PHONE_DEVICE_ID -ErrorAction SilentlyContinue
    Remove-Item Env:\PHONE_OWNER_TOKEN -ErrorAction SilentlyContinue
}

$relayHealth = "http://127.0.0.1:$RelayPort/healthz"
if (-not (Wait-HttpOk $relayHealth 10)) {
    throw "Node relay did not become healthy at $relayHealth"
}

Write-Host "Local Node relay started:"
Write-Host "http://127.0.0.1:$RelayPort"
Write-Host "Node PID: $($nodeProcess.Id)"

if ($NoTunnel) {
    Write-Host "Cloudflared tunnel skipped."
    exit 0
}

if (-not (Test-Path -LiteralPath $CloudflaredPath)) {
    throw "cloudflared not found: $CloudflaredPath"
}
Remove-Item -LiteralPath $CloudflaredLog -Force -ErrorAction SilentlyContinue
$cloudArgs = @(
    "tunnel",
    "--url", "http://127.0.0.1:$RelayPort",
    "--no-autoupdate",
    "--loglevel", "info",
    "--logfile", $CloudflaredLog
)
$cloudflaredProcess = Start-Process -FilePath $CloudflaredPath -ArgumentList $cloudArgs -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $CloudflaredPidFile -Value $cloudflaredProcess.Id -NoNewline

$publicBaseUrl = ""
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $publicBaseUrl = Read-TryCloudflareUrl
    if ($publicBaseUrl) {
        break
    }
}

Write-Host "Cloudflared PID: $($cloudflaredProcess.Id)"
Write-Host "Cloudflared log:"
Write-Host $CloudflaredLog
if ($publicBaseUrl) {
    Write-Host "Temporary relay base URL:"
    Write-Host $publicBaseUrl
    Write-Host "Temporary MCP URL:"
    Write-Host "$publicBaseUrl/d/$DeviceId/mcp"
    if ($ConfigurePhone) {
        $configureScript = Join-Path $PSScriptRoot "configure-phone-relay.ps1"
        if (-not (Test-Path -LiteralPath $configureScript)) {
            Write-Host "Phone auto-config skipped; configure script missing: $configureScript"
        } elseif (-not (Test-Path -LiteralPath $AdbPath)) {
            Write-Host "Phone auto-config skipped; adb not found: $AdbPath"
        } else {
            Write-Host "Configuring connected Android phone to use the temporary relay URL..."
            try {
                powershell -NoProfile -ExecutionPolicy Bypass -File $configureScript -RelayBaseUrl $publicBaseUrl -DeviceId $DeviceId -AdbPath $AdbPath *> $PhoneConfigureLog
                Write-Host "Phone auto-config completed. Log:"
                Write-Host $PhoneConfigureLog
            } catch {
                Write-Host "Phone auto-config failed: $($_.Exception.Message)"
                Write-Host "Log:"
                Write-Host $PhoneConfigureLog
            }
        }
    }
} else {
    Write-Host "Temporary relay URL was not found in the log yet. Check the log path above."
}
