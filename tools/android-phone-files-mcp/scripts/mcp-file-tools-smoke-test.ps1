param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,

    [Parameter(Mandatory = $true)]
    [string]$McpUrl,

    [string]$ProbeDir = "Download/devspace_tool_probe"
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
    $response = Invoke-RestMethod -Uri $McpUrl -Method Post -Headers $Headers -Body $body -TimeoutSec 30
    if ($response.error) {
        throw ($response.error | ConvertTo-Json -Compress)
    }
    $text = $response.result.content[0].text
    Write-Host "$Name => $text"
    return $text
}

$blob = "$ProbeDir/blob.bin"
$copy = "$ProbeDir/blob-copy.bin"
$moved = "$ProbeDir/blob-moved.bin"
$chunked = "$ProbeDir/chunked.bin"
$zipPath = "Download/devspace_tool_probe.zip"
$unzipDir = "Download/devspace_tool_unzip_probe"
$expectedBase64 = "aGVsbG8tZnJvbS1ncHQ="
$chunk1Text = "chunk-alpha-"
$chunk2Text = "chunk-beta"
$chunk1Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($chunk1Text))
$chunk2Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($chunk2Text))
$expectedChunkText = $chunk1Text + $chunk2Text

Invoke-McpTool 1 "make_directory" @{ path = $ProbeDir } | Out-Null
Invoke-McpTool 2 "write_file_base64" @{ path = $blob; content_base64 = $expectedBase64 } | Out-Null
Invoke-McpTool 3 "stat_path" @{ path = $blob } | Out-Null
Invoke-McpTool 4 "copy_path" @{ from = $blob; to = $copy; overwrite = $true } | Out-Null
Invoke-McpTool 5 "move_path" @{ from = $copy; to = $moved; overwrite = $true } | Out-Null
$actualBase64 = Invoke-McpTool 6 "read_file_base64" @{ path = $moved }
if ($actualBase64.Trim() -ne $expectedBase64) {
    throw "Base64 roundtrip failed. Expected $expectedBase64, got $actualBase64"
}
Invoke-McpTool 7 "write_file_chunk_base64" @{ path = $chunked; offset = 0; content_base64 = $chunk1Base64; truncate_before_write = $true } | Out-Null
Invoke-McpTool 8 "write_file_chunk_base64" @{ path = $chunked; offset = $chunk1Text.Length; content_base64 = $chunk2Base64; truncate_after_write = $true } | Out-Null
$chunkJsonText = Invoke-McpTool 9 "read_file_chunk_base64" @{ path = $chunked; offset = 0; length = $expectedChunkText.Length }
$chunkJson = $chunkJsonText | ConvertFrom-Json
$actualChunkText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($chunkJson.content_base64))
if ($actualChunkText -ne $expectedChunkText -or -not $chunkJson.eof) {
    throw "Chunk roundtrip failed. Expected $expectedChunkText, got $actualChunkText"
}
$hashJsonText = Invoke-McpTool 10 "hash_file" @{ path = $chunked; algorithm = "SHA-256" }
$hashJson = $hashJsonText | ConvertFrom-Json
$expectedHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($expectedChunkText))).Replace("-", "").ToLowerInvariant()
if ($hashJson.hash -ne $expectedHash -or [int64]$hashJson.bytes -ne [int64]$expectedChunkText.Length) {
    throw "hash_file failed. Expected $expectedHash, got $($hashJson.hash)"
}
$findText = Invoke-McpTool 11 "find_files" @{ query = "chunked"; path = $ProbeDir; limit = 10 }
if ($findText -notmatch "chunked\.bin") {
    throw "find_files failed to locate chunked.bin. Output: $findText"
}
Invoke-McpTool 12 "scan_media" @{ path = $chunked } | Out-Null
Invoke-McpTool 13 "zip_paths" @{ paths = @($ProbeDir); output_path = $zipPath; overwrite = $true } | Out-Null
Invoke-McpTool 14 "unzip_file" @{ zip_path = $zipPath; destination_path = $unzipDir; overwrite = $true } | Out-Null
$unzipFindText = Invoke-McpTool 15 "find_files" @{ query = "chunked"; path = $unzipDir; limit = 10 }
if ($unzipFindText -notmatch "chunked\.bin") {
    throw "unzip_file failed to extract chunked.bin. Output: $unzipFindText"
}
Invoke-McpTool 16 "delete_path" @{ path = $ProbeDir; recursive = $true } | Out-Null
Invoke-McpTool 17 "delete_path" @{ path = $zipPath } | Out-Null
Invoke-McpTool 18 "delete_path" @{ path = $unzipDir; recursive = $true } | Out-Null
Write-Host "MCP file-tools smoke test passed for $McpUrl"
