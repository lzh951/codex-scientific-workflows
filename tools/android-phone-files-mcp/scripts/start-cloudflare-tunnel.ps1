param(
    [string]$CloudflaredPath = "$PSScriptRoot\..\tools\cloudflared.exe",
    [int]$HostPort = 17676,
    [int]$WaitSeconds = 20
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CloudflaredPath)) {
    throw "cloudflared not found: $CloudflaredPath"
}

$out = Join-Path $PSScriptRoot "..\cloudflared.out.log"
$err = Join-Path $PSScriptRoot "..\cloudflared.err.log"
$urlFile = Join-Path $PSScriptRoot "..\cloudflare-mcp-url.txt"
Remove-Item $out, $err, $urlFile -ErrorAction SilentlyContinue

Start-Process -WindowStyle Hidden `
    -FilePath $CloudflaredPath `
    -ArgumentList @("tunnel", "--url", "http://127.0.0.1:$HostPort", "--no-autoupdate") `
    -RedirectStandardOutput $out `
    -RedirectStandardError $err `
    -WorkingDirectory (Resolve-Path (Join-Path $PSScriptRoot ".."))

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$publicUrl = $null
while ((Get-Date) -lt $deadline -and -not $publicUrl) {
    Start-Sleep -Seconds 1
    $log = (Get-Content $out, $err -ErrorAction SilentlyContinue) -join "`n"
    $match = [regex]::Match($log, "https://[a-z0-9-]+\.trycloudflare\.com")
    if ($match.Success) {
        $publicUrl = $match.Value
    }
}

if (-not $publicUrl) {
    Get-Content $out, $err -ErrorAction SilentlyContinue
    throw "Timed out waiting for cloudflared quick tunnel URL."
}

$mcpUrl = "$publicUrl/mcp"
Set-Content -LiteralPath $urlFile -Value $mcpUrl -Encoding ASCII
Write-Host "Public MCP URL: $mcpUrl"
Write-Host "Saved to: $urlFile"
