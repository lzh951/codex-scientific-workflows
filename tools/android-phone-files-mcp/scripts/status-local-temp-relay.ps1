param(
    [string]$DeviceId = "phone-example",
    [int]$RelayPort = 8788
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$RuntimeDir = Join-Path $ProjectRoot "runtime"
$NodePidFile = Join-Path $RuntimeDir "local-relay-node.pid"
$CloudflaredPidFile = Join-Path $RuntimeDir "local-relay-cloudflared.pid"
$CloudflaredLog = Join-Path $RuntimeDir "local-relay-cloudflared.log"

function Get-PidStatus([string]$Label, [string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return "$Label PID file: missing"
    }
    $pidText = (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Select-Object -First 1)
    $process = if ($pidText) { Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue } else { $null }
    if ($process) {
        return "$Label PID ${pidText}: running"
    }
    return "$Label PID ${pidText}: not running"
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

Write-Host (Get-PidStatus "Node relay" $NodePidFile)
Write-Host (Get-PidStatus "Cloudflared" $CloudflaredPidFile)

Write-Host "Local port state:"
Get-NetTCPConnection -LocalPort $RelayPort -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,State,OwningProcess |
    Format-Table -AutoSize

$localHealth = "http://127.0.0.1:$RelayPort/healthz"
try {
    Write-Host "Local relay health: $localHealth"
    Invoke-RestMethod -Uri $localHealth -TimeoutSec 5 | ConvertTo-Json -Compress
} catch {
    Write-Host $_.Exception.Message
}

$publicBaseUrl = Read-TryCloudflareUrl
if ($publicBaseUrl) {
    $publicHealth = "$publicBaseUrl/d/$DeviceId/healthz"
    Write-Host "Temporary relay base URL:"
    Write-Host $publicBaseUrl
    Write-Host "Temporary MCP URL:"
    Write-Host "$publicBaseUrl/d/$DeviceId/mcp"
    try {
        Write-Host "Public phone health: $publicHealth"
        Invoke-RestMethod -Uri $publicHealth -TimeoutSec 20 | ConvertTo-Json -Compress
    } catch {
        Write-Host $_.Exception.Message
    }
} else {
    Write-Host "Temporary relay URL: not found in $CloudflaredLog"
}
