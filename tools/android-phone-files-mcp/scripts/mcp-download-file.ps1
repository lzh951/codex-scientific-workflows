param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,

    [Parameter(Mandatory = $true)]
    [string]$McpUrl,

    [Parameter(Mandatory = $true)]
    [string]$PhonePath,

    [Parameter(Mandatory = $true)]
    [string]$LocalPath,

    [int]$ChunkBytes = 1048576,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
if ($ChunkBytes -le 0 -or $ChunkBytes -gt 4194304) {
    throw "ChunkBytes must be between 1 and 4194304."
}

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

$localDir = Split-Path -Parent $LocalPath
if ($localDir) {
    New-Item -ItemType Directory -Force -Path $localDir | Out-Null
}

$remoteHash = $null
if (-not $SkipVerify) {
    $remoteHashText = Invoke-McpTool 1000000 "hash_file" @{ path = $PhonePath; algorithm = "SHA-256" }
    $remoteHash = $remoteHashText | ConvertFrom-Json
}

$stream = [System.IO.File]::Open($LocalPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
try {
    $offset = [int64]0
    $id = 1
    while ($true) {
        $text = Invoke-McpTool $id "read_file_chunk_base64" @{
            path = $PhonePath
            offset = $offset
            length = $ChunkBytes
        }
        $chunk = $text | ConvertFrom-Json
        $bytes = [Convert]::FromBase64String([string]$chunk.content_base64)
        if ($bytes.Length -gt 0) {
            $stream.Write($bytes, 0, $bytes.Length)
        }
        $offset = [int64]$chunk.nextOffset
        Write-Host "Downloaded $offset / $($chunk.fileBytes) bytes <- $PhonePath"
        $id++
        if ($chunk.eof) {
            break
        }
    }
} finally {
    $stream.Dispose()
}

Write-Host "Download complete:"
Write-Host "$PhonePath -> $LocalPath"

if (-not $SkipVerify) {
    $localFile = Get-Item -LiteralPath $LocalPath
    $localHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $LocalPath).Hash.ToLowerInvariant()
    if ([string]$remoteHash.hash -ne $localHash -or [int64]$remoteHash.bytes -ne [int64]$localFile.Length) {
        throw "Downloaded file hash verification failed. Local $localHash ($($localFile.Length) bytes), remote $($remoteHash.hash) ($($remoteHash.bytes) bytes)."
    }
    Write-Host "Download SHA256 verified:"
    Write-Host $localHash
}
