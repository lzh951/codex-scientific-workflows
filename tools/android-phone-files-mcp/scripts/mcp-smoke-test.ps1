param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,
    [string]$McpUrl = "http://127.0.0.1:17676/mcp",
    [string]$ProbePath = "Download/devspace_android_mcp_probe.txt"
)

$ErrorActionPreference = "Stop"

$headers = @{
    Authorization = "Bearer $OwnerToken"
    "Content-Type" = "application/json"
    "MCP-Protocol-Version" = "2025-06-18"
}

function Invoke-Mcp {
    param(
        [int]$Id,
        [string]$Method,
        [hashtable]$Params = @{}
    )
    $body = @{
        jsonrpc = "2.0"
        id = $Id
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 8 -Compress
    Invoke-RestMethod -Uri $McpUrl -Method Post -Headers $headers -Body $body
}

function Invoke-Tool {
    param(
        [int]$Id,
        [string]$Name,
        [hashtable]$Arguments = @{}
    )
    Invoke-Mcp -Id $Id -Method "tools/call" -Params @{
        name = $Name
        arguments = $Arguments
    }
}

Write-Host "Initializing MCP..."
Invoke-Mcp -Id 1 -Method "initialize" -Params @{
    protocolVersion = "2025-06-18"
    capabilities = @{}
    clientInfo = @{
        name = "desktop-smoke-test"
        version = "0.1"
    }
} | ConvertTo-Json -Depth 8 -Compress

Write-Host "Listing tools..."
Invoke-Mcp -Id 2 -Method "tools/list" | ConvertTo-Json -Depth 8 -Compress

Write-Host "Opening phone workspace..."
Invoke-Tool -Id 3 -Name "open_workspace" -Arguments @{ path = "." } | ConvertTo-Json -Depth 8 -Compress

$probeText = "DevSpace Android MCP probe from desktop on $(Get-Date -Format yyyy-MM-ddTHH:mm:ssK)."
Write-Host "Writing probe: $ProbePath"
Invoke-Tool -Id 4 -Name "write_file" -Arguments @{
    path = $ProbePath
    content = $probeText
} | ConvertTo-Json -Depth 8 -Compress

Write-Host "Reading probe back..."
Invoke-Tool -Id 5 -Name "read_file" -Arguments @{
    path = $ProbePath
} | ConvertTo-Json -Depth 8 -Compress

Write-Host "Smoke test complete."
