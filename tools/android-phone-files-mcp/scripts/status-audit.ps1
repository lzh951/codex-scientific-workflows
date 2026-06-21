param(
    [string]$AdbPath = "adb.exe",
    [string]$McpUrlFile = "$PSScriptRoot\..\cloudflare-mcp-url.txt",
    [string]$OwnerToken = "",
    [int]$HostPort = 17676
)

$ErrorActionPreference = "Stop"

function Section {
    param([string]$Name)
    Write-Host ""
    Write-Host "== $Name =="
}

function Try-Step {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    Write-Host "-- $Name"
    try {
        & $Block
    } catch {
        Write-Host "FAILED: $($_.Exception.Message)"
    }
}

Section "Device"
Try-Step "adb devices" {
    & $AdbPath devices -l
}

Section "Local MCP"
Try-Step "local health" {
    Invoke-RestMethod -Uri "http://127.0.0.1:$HostPort/healthz" | ConvertTo-Json -Compress
}

Section "Permissions"
Try-Step "appops storage/media" {
    & $AdbPath shell appops get com.lzh.devspaceandroid |
        Select-String -Pattern "MANAGE_EXTERNAL_STORAGE|READ_MEDIA|ACCESS_MEDIA|READ_EXTERNAL|WRITE_EXTERNAL"
}

Section "Public MCP"
if (Test-Path -LiteralPath $McpUrlFile) {
    $mcpUrl = (Get-Content -LiteralPath $McpUrlFile -Raw).Trim()
    Write-Host "MCP URL: $mcpUrl"
    $base = $mcpUrl -replace "/mcp$", ""
    Try-Step "public health" {
        Invoke-RestMethod -Uri "$base/healthz" | ConvertTo-Json -Compress
    }
    Try-Step "oauth protected-resource metadata" {
        Invoke-RestMethod -Uri "$base/.well-known/oauth-protected-resource/mcp" | ConvertTo-Json -Depth 8 -Compress
    }
    Try-Step "oauth authorization metadata" {
        Invoke-RestMethod -Uri "$base/.well-known/oauth-authorization-server/mcp" | ConvertTo-Json -Depth 8 -Compress
    }
    if ($OwnerToken) {
        Try-Step "tools/list" {
            $headers = @{
                Authorization = "Bearer $OwnerToken"
                "Content-Type" = "application/json"
                "MCP-Protocol-Version" = "2025-06-18"
            }
            $body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
            Invoke-RestMethod -Uri $mcpUrl -Method Post -Headers $headers -Body $body | ConvertTo-Json -Depth 8 -Compress
        }
        Try-Step "list_roots" {
            $headers = @{
                Authorization = "Bearer $OwnerToken"
                "Content-Type" = "application/json"
                "MCP-Protocol-Version" = "2025-06-18"
            }
            $body = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_roots","arguments":{}}}'
            Invoke-RestMethod -Uri $mcpUrl -Method Post -Headers $headers -Body $body | ConvertTo-Json -Depth 8 -Compress
        }
    } else {
        Write-Host "OwnerToken not provided; skipping authenticated MCP calls."
    }
} else {
    Write-Host "MCP URL file not found: $McpUrlFile"
}
