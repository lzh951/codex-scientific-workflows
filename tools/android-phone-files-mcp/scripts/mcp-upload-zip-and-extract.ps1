param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,

    [Parameter(Mandatory = $true)]
    [string]$McpUrl,

    [Parameter(Mandatory = $true)]
    [string]$LocalZipPath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPhonePath,

    [string]$TempPhoneZipPath = "",
    [int]$ChunkBytes = 1048576,
    [switch]$Overwrite,
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

if (-not (Test-Path -LiteralPath $LocalZipPath)) {
    throw "Local zip not found: $LocalZipPath"
}
if (-not $TempPhoneZipPath) {
    $TempPhoneZipPath = "Download/devspace-import-" + [guid]::NewGuid().ToString("N") + ".zip"
}

try {
    $uploadScript = Join-Path $PSScriptRoot "mcp-upload-file.ps1"
    powershell -NoProfile -ExecutionPolicy Bypass -File $uploadScript -OwnerToken $OwnerToken -McpUrl $McpUrl -LocalPath $LocalZipPath -PhonePath $TempPhoneZipPath -ChunkBytes $ChunkBytes

    $unzipText = Invoke-McpTool 1 "unzip_file" @{
        zip_path = $TempPhoneZipPath
        destination_path = $DestinationPhonePath
        overwrite = $Overwrite.IsPresent
    }
    Write-Host "Phone unzip result:"
    Write-Host $unzipText
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

Write-Host "Zip uploaded and extracted:"
Write-Host "$LocalZipPath -> $DestinationPhonePath"
