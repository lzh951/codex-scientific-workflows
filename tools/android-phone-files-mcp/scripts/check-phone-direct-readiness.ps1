param(
    [string]$AdbPath = "adb.exe",
    [int]$HostPort = 17676,
    [string]$McpUrl = "",
    [string]$OwnerToken = "",
    [switch]$RequirePermanentRelay,
    [switch]$SkipMcpRoundTrip
)

$ErrorActionPreference = "Stop"
$PackageName = "com.lzh.devspaceandroid"

function Invoke-HealthGet([string]$Url, [int]$TimeoutSec) {
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -fsS --max-time $TimeoutSec $Url
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed for $Url"
        }
        return
    }
    Invoke-RestMethod -Uri $Url -TimeoutSec $TimeoutSec | ConvertTo-Json -Compress
}

function First-Match([string]$Text, [string]$Pattern) {
    $match = [regex]::Match($Text, $Pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return $null
}

function Read-PhonePrefs {
    if (-not (Test-Path -LiteralPath $AdbPath)) {
        return ""
    }
    $devices = & $AdbPath devices -l
    $activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
    if ($activeDevices.Count -eq 0) {
        return ""
    }
    $prefs = & $AdbPath shell run-as $PackageName cat shared_prefs/devspace_android.xml 2>$null
    return $prefs -join "`n"
}

function Invoke-McpRequest([int]$Id, [string]$Method, [object]$ParamsObj) {
    $body = @{
        jsonrpc = "2.0"
        id = $Id
        method = $Method
        params = $ParamsObj
    } | ConvertTo-Json -Depth 12 -Compress
    Invoke-RestMethod -Uri $McpUrl -Method Post -Headers $script:Headers -Body $body -TimeoutSec 60
}

function Invoke-McpTool([int]$Id, [string]$Name, [hashtable]$ToolArgs) {
    Invoke-McpRequest $Id "tools/call" @{
        name = $Name
        arguments = $ToolArgs
    }
}

$relayStatus = $null
if (Test-Path -LiteralPath $AdbPath) {
    $devices = & $AdbPath devices -l
    $activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
    if ($activeDevices.Count -gt 0) {
        try {
            & $AdbPath forward --remove "tcp:$HostPort" 2>$null | Out-Null
            & $AdbPath forward "tcp:$HostPort" "tcp:7676" | Out-Null
            $relayStatus = Invoke-RestMethod -Uri "http://127.0.0.1:$HostPort/relay_status" -TimeoutSec 12
            if (-not $McpUrl) {
                $McpUrl = $relayStatus.publicMcpUrl
            }
        } catch {
            Write-Host "Could not read local relay status: $($_.Exception.Message)"
        }
    }
}

$prefsText = Read-PhonePrefs
if (-not $OwnerToken) {
    $OwnerToken = First-Match $prefsText '<string name="owner_token">([^<]+)</string>'
}
if (-not $McpUrl) {
    throw "McpUrl is required when the phone relay status is not available through ADB."
}
if (-not $OwnerToken -and -not $SkipMcpRoundTrip) {
    throw "OwnerToken is required for MCP round-trip verification."
}

$baseUrl = $McpUrl -replace "/mcp$", ""
$healthUrl = $McpUrl -replace "/mcp$", "/healthz"
$isTryCloudflare = $McpUrl -match "\.trycloudflare\.com/"
$isLocal = $McpUrl -match "https?://(127\.0\.0\.1|localhost)(:|/)"

Write-Host "MCP URL:"
Write-Host $McpUrl
Write-Host "Health URL:"
Write-Host $healthUrl

if ($relayStatus) {
    Write-Host "Local relay status:"
    $relayStatus | Select-Object relayBaseUrl,publicMcpUrl,mcpRunning,powerLocksHeld,watchdogStatus,watchdogRestartCount,lastWatchdogOkAt,running,status,lastMessage | ConvertTo-Json -Compress
}

Write-Host "Public health:"
Invoke-HealthGet $healthUrl 30

$script:Headers = @{
    Authorization = "Bearer $OwnerToken"
    "Content-Type" = "application/json"
}

Write-Host "MCP initialize:"
$serverInfo = (Invoke-McpRequest 1 "initialize" @{}).result.serverInfo
$serverInfo | ConvertTo-Json -Compress

if (-not $SkipMcpRoundTrip) {
    Write-Host "MCP file round trip:"
    $testPath = "Download/devspace-readiness-check.txt"
    $expected = "devspace readiness check"
    $write = Invoke-McpTool 2 "write_file" @{ path = $testPath; content = $expected }
    $read = Invoke-McpTool 3 "read_file" @{ path = $testPath }
    $delete = Invoke-McpTool 4 "delete_path" @{ path = $testPath }
    $actual = $read.result.content[0].text
    if ($actual -ne $expected) {
        throw "MCP file round trip mismatch. Expected '$expected', got '$actual'."
    }
    [pscustomobject]@{
        write = $write.result.content[0].text
        read = $actual
        delete = $delete.result.content[0].text
    } | ConvertTo-Json -Compress
}

$permanentReady = -not $isTryCloudflare -and -not $isLocal
Write-Host "Permanent relay readiness:"
[pscustomobject]@{
    permanentReady = $permanentReady
    usesTryCloudflare = $isTryCloudflare
    usesLocalhost = $isLocal
    mcpUrl = $McpUrl
    serverVersion = $serverInfo.version
} | ConvertTo-Json -Compress

if ($RequirePermanentRelay -and -not $permanentReady) {
    throw "Current MCP URL is still temporary or local. This is not a final no-PC relay: $McpUrl"
}
