param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,

    [Parameter(Mandatory = $true)]
    [string]$McpUrl,

    [Parameter(Mandatory = $true)]
    [string[]]$PhonePaths,

    [Parameter(Mandatory = $true)]
    [string]$LocalZipPath,

    [string]$TempPhoneZipPath = "",
    [int]$ChunkBytes = 1048576,
    [switch]$KeepPhoneZip
)

$ErrorActionPreference = "Stop"
$Headers = @{
    Authorization = "Bearer $OwnerToken"
    "Content-Type" = "application/json"
}

function Invoke-McpTool([int]$Id, [string]$Name, [hashtable]$Arguments) {
    $body = @{
        jsonrpc = "2.0"
        id = $Id
        method = "tools/call"
        params = @{
            name = $Name
            arguments = $Arguments
        }
    } | ConvertTo-Json -Depth 8 -Compress
    $response = Invoke-RestMethod -Uri $McpUrl -Method Post -Headers $Headers -Body $body -TimeoutSec 120
    if ($response.error) {
        throw ($response.error | ConvertTo-Json -Compress)
    }
    $text = $response.result.content[0].text
    if ($response.result.isError) {
        throw $text
    }
    return $text
}

if (-not $TempPhoneZipPath) {
    $TempPhoneZipPath = "Download/devspace-export-" + [guid]::NewGuid().ToString("N") + ".zip"
}

try {
    $zipText = Invoke-McpTool 1 "zip_paths" @{
        paths = $PhonePaths
        output_path = $TempPhoneZipPath
        overwrite = $true
    }
    Write-Host "Phone zip created:"
    Write-Host $zipText

    $downloadScript = Join-Path $PSScriptRoot "mcp-download-file.ps1"
    powershell -NoProfile -ExecutionPolicy Bypass -File $downloadScript -OwnerToken $OwnerToken -McpUrl $McpUrl -PhonePath $TempPhoneZipPath -LocalPath $LocalZipPath -ChunkBytes $ChunkBytes
} finally {
    if (-not $KeepPhoneZip) {
        try {
            Invoke-McpTool 999001 "delete_path" @{ path = $TempPhoneZipPath } | Out-Null
            Write-Host "Deleted temporary phone zip:"
            Write-Host $TempPhoneZipPath
        } catch {
            Write-Host "Could not delete temporary phone zip: $($_.Exception.Message)"
        }
    }
}

Write-Host "Phone paths downloaded as zip:"
Write-Host ($PhonePaths -join ", ")
Write-Host $LocalZipPath
