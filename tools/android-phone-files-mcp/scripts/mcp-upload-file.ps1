param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,

    [Parameter(Mandatory = $true)]
    [string]$McpUrl,

    [Parameter(Mandatory = $true)]
    [string]$LocalPath,

    [Parameter(Mandatory = $true)]
    [string]$PhonePath,

    [int]$ChunkBytes = 1048576,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
if ($ChunkBytes -le 0 -or $ChunkBytes -gt 4194304) {
    throw "ChunkBytes must be between 1 and 4194304."
}
if (-not (Test-Path -LiteralPath $LocalPath)) {
    throw "Local file not found: $LocalPath"
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

$file = Get-Item -LiteralPath $LocalPath
$stream = [System.IO.File]::OpenRead($file.FullName)
try {
    $buffer = New-Object byte[] $ChunkBytes
    $offset = [int64]0
    $id = 1
    if ($file.Length -eq 0) {
        Invoke-McpTool $id "write_file_chunk_base64" @{
            path = $PhonePath
            offset = 0
            content_base64 = ""
            truncate_before_write = $true
            truncate_after_write = $true
        } | Out-Null
        Write-Host "Uploaded empty file to $PhonePath"
        exit 0
    }
    while ($true) {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) {
            break
        }
        $base64 = [Convert]::ToBase64String($buffer, 0, $read)
        $isFirst = $offset -eq 0
        $isLast = ($offset + $read) -ge $file.Length
        $result = Invoke-McpTool $id "write_file_chunk_base64" @{
            path = $PhonePath
            offset = $offset
            content_base64 = $base64
            truncate_before_write = $isFirst
            truncate_after_write = $isLast
        }
        $offset += $read
        $id++
        Write-Host "Uploaded $offset / $($file.Length) bytes -> $PhonePath"
        $result | Out-Null
    }
} finally {
    $stream.Dispose()
}

Write-Host "Upload complete:"
Write-Host "$($file.FullName) -> $PhonePath"

if (-not $SkipVerify) {
    $localHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $remoteHashText = Invoke-McpTool 1000001 "hash_file" @{ path = $PhonePath; algorithm = "SHA-256" }
    $remoteHash = $remoteHashText | ConvertFrom-Json
    if ([string]$remoteHash.hash -ne $localHash -or [int64]$remoteHash.bytes -ne [int64]$file.Length) {
        throw "Remote hash verification failed. Local $localHash ($($file.Length) bytes), remote $($remoteHash.hash) ($($remoteHash.bytes) bytes)."
    }
    Write-Host "Upload SHA256 verified:"
    Write-Host $localHash
}
