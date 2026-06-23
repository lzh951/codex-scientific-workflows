param(
    [string]$AdbPath = "adb.exe",
    [string]$WorkerDir = "$PSScriptRoot\..\relay\cloudflare-worker",
    [string]$DeviceId = "",
    [string]$OwnerToken = "",
    [string]$RelayBaseUrl = "",
    [string]$FallbackRelayBaseUrl = "",
    [int]$HostPort = 17676,
    [switch]$Temporary,
    [switch]$NoRevertOnFailure,
    [switch]$SkipMcpRoundTrip
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$WorkerDir = (Resolve-Path $WorkerDir).Path
$PackageName = "com.lzh.devspaceandroid"

function Invoke-Adb {
    $AdbArgs = $args
    & $AdbPath @AdbArgs
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: $($AdbArgs -join ' ')"
    }
}

function First-Match([string]$Text, [string]$Pattern) {
    $match = [regex]::Match($Text, $Pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return $null
}

function Ensure-AdbDevice {
    if (-not (Test-Path -LiteralPath $AdbPath)) {
        throw "adb not found: $AdbPath"
    }
    $devices = & $AdbPath devices -l
    $activeDevices = @($devices | Select-String -Pattern "\bdevice\b")
    if ($activeDevices.Count -eq 0) {
        throw "No ADB device is connected. Connect the phone once, enable USB debugging, then rerun this script."
    }
}

function Read-PhonePrefs {
    & $AdbPath shell am start --user 0 -W -n "$PackageName/.MainActivity" | Out-Null
    $prefs = & $AdbPath shell run-as $PackageName cat shared_prefs/devspace_android.xml 2>$null
    return $prefs -join "`n"
}

function Set-WorkerSecret([string]$Name, [string]$Value) {
    if (-not $Value) {
        return
    }
    Write-Host "Setting Cloudflare Worker secret: $Name"
    $Value | npx wrangler secret put $Name
    if ($LASTEXITCODE -ne 0) {
        throw "wrangler secret put failed for $Name"
    }
}

function Parse-WorkerUrl([string]$Text) {
    $matches = [regex]::Matches($Text, 'https://[A-Za-z0-9.-]+\.workers\.dev')
    if ($matches.Count -eq 0) {
        return ""
    }
    return $matches[$matches.Count - 1].Value.TrimEnd("/")
}

function Ensure-WranglerAuth {
    if ($Temporary) {
        return
    }
    $whoami = (& npx wrangler whoami 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $whoami -match "not authenticated") {
        throw "Cloudflare is not authenticated. Run: cd <repo>\tools\android-phone-files-mcp\relay\cloudflare-worker ; npx wrangler login"
    }
}

function Deploy-Worker {
    Push-Location $WorkerDir
    try {
        Ensure-WranglerAuth
        if ($Temporary) {
            Write-Host "Deploying temporary Cloudflare Worker preview..."
            $output = (& npx wrangler deploy --temporary 2>&1) -join "`n"
            Write-Host $output
            $url = Parse-WorkerUrl $output
            if (-not $url) {
                throw "Could not parse temporary Worker URL from Wrangler output."
            }
            return $url
        }

        Write-Host "Deploying permanent Cloudflare Worker relay..."
        $output = (& npx wrangler deploy 2>&1) -join "`n"
        Write-Host $output
        if ($LASTEXITCODE -ne 0) {
            throw "wrangler deploy failed."
        }

        Set-WorkerSecret "PHONE_DEVICE_ID" $DeviceId
        Set-WorkerSecret "PHONE_OWNER_TOKEN" $OwnerToken

        Write-Host "Redeploying Worker after secret updates..."
        $output = (& npx wrangler deploy 2>&1) -join "`n"
        Write-Host $output
        if ($LASTEXITCODE -ne 0) {
            throw "wrangler deploy failed after secret updates."
        }
        $url = Parse-WorkerUrl $output
        if (-not $url) {
            throw "Could not parse Worker URL from Wrangler output. Pass -RelayBaseUrl explicitly."
        }
        return $url
    } finally {
        Pop-Location
    }
}

function Configure-PhoneRelay([string]$BaseUrl, [switch]$SkipVerify) {
    $script = Join-Path $ProjectRoot "scripts\configure-phone-relay.ps1"
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $script,
        "-RelayBaseUrl",
        $BaseUrl,
        "-DeviceId",
        $DeviceId,
        "-AdbPath",
        $AdbPath,
        "-HostPort",
        [string]$HostPort
    )
    if ($SkipVerify) {
        $args += "-SkipVerify"
    }
    & powershell @args
    if ($LASTEXITCODE -ne 0) {
        throw "configure-phone-relay.ps1 failed for $BaseUrl"
    }
}

function Test-McpRoundTrip([string]$BaseUrl) {
    if ($SkipMcpRoundTrip) {
        return
    }
    $mcpUrl = "$BaseUrl/d/$DeviceId/mcp"
    $headers = @{
        Authorization = "Bearer $OwnerToken"
        "Content-Type" = "application/json"
    }
    function Invoke-McpTool([int]$Id, [string]$Name, [hashtable]$ToolArgs) {
        $body = @{
            jsonrpc = "2.0"
            id = $Id
            method = "tools/call"
            params = @{
                name = $Name
                arguments = $ToolArgs
            }
        } | ConvertTo-Json -Depth 10 -Compress
        Invoke-RestMethod -Uri $mcpUrl -Method Post -Headers $headers -Body $body -TimeoutSec 60
    }

    $path = "Download/devspace-worker-finalize-verify.txt"
    $expected = "worker finalize verify"
    $write = Invoke-McpTool 1 "write_file" @{ path = $path; content = $expected }
    $read = Invoke-McpTool 2 "read_file" @{ path = $path }
    $delete = Invoke-McpTool 3 "delete_path" @{ path = $path }
    $actual = $read.result.content[0].text
    if ($actual -ne $expected) {
        throw "MCP round trip mismatch. Expected '$expected', got '$actual'."
    }
    Write-Host "MCP file round trip succeeded:"
    Write-Host $write.result.content[0].text
    Write-Host $delete.result.content[0].text
}

Ensure-AdbDevice
$prefsText = Read-PhonePrefs
if (-not $OwnerToken) {
    $OwnerToken = First-Match $prefsText '<string name="owner_token">([^<]+)</string>'
}
if (-not $DeviceId) {
    $DeviceId = First-Match $prefsText '<string name="relay_device_id">([^<]+)</string>'
}
if (-not $FallbackRelayBaseUrl) {
    $FallbackRelayBaseUrl = First-Match $prefsText '<string name="relay_base_url">([^<]+)</string>'
}
if (-not $DeviceId) {
    $serial = (& $AdbPath get-serialno).Trim()
    $DeviceId = "phone-" + ($serial -replace "[^A-Za-z0-9_.-]", "")
}
if (-not $OwnerToken) {
    throw "Could not read owner token from the Android app. Open the app once, then rerun this script."
}

Write-Host "Device ID:"
Write-Host $DeviceId
Write-Host "Fallback relay base URL:"
Write-Host $FallbackRelayBaseUrl

if (-not $RelayBaseUrl) {
    $RelayBaseUrl = Deploy-Worker
}
$RelayBaseUrl = $RelayBaseUrl.TrimEnd("/")

try {
    Write-Host "Configuring phone for Cloudflare Worker relay:"
    Write-Host $RelayBaseUrl
    Configure-PhoneRelay $RelayBaseUrl
    Test-McpRoundTrip $RelayBaseUrl
    Write-Host "Permanent relay candidate is working:"
    Write-Host "$RelayBaseUrl/d/$DeviceId/mcp"
} catch {
    $message = $_.Exception.Message
    Write-Host "Cloudflare Worker relay finalization failed: $message"
    if ($FallbackRelayBaseUrl -and -not $NoRevertOnFailure) {
        Write-Host "Reverting phone to fallback relay:"
        Write-Host $FallbackRelayBaseUrl
        Configure-PhoneRelay $FallbackRelayBaseUrl -SkipVerify
    }
    throw
}
