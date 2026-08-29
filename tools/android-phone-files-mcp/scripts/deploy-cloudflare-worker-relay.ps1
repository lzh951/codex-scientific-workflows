param(
    [string]$WorkerDir = "$PSScriptRoot\..\relay\cloudflare-worker",
    [string]$DeviceId = "phone-example",
    [string]$OwnerToken = "",
    [switch]$SkipSecrets,
    [switch]$SkipDeploy,
    [switch]$Temporary
)

$ErrorActionPreference = "Stop"
$WorkerDir = (Resolve-Path $WorkerDir).Path

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm was not found. Install Node.js first, then rerun this script."
}

function Set-WorkerSecret([string]$Name, [string]$Value) {
    if (-not $Value) {
        return
    }
    Write-Host "Setting Worker secret: $Name"
    $Value | npx wrangler secret put $Name
    if ($LASTEXITCODE -ne 0) {
        throw "wrangler secret put failed for $Name"
    }
}

Push-Location $WorkerDir
try {
    Write-Host "Cloudflare Worker directory:"
    Write-Host $WorkerDir

    if ($Temporary -and -not $SkipSecrets) {
        Write-Host "Temporary Wrangler deployments do not keep project secrets. Continuing with -SkipSecrets behavior."
        $SkipSecrets = $true
    }

    if (-not $SkipDeploy) {
        Write-Host "Deploying Cloudflare Worker relay..."
        if ($Temporary) {
            npx wrangler deploy --temporary
        } else {
            npx wrangler deploy
        }
        if ($LASTEXITCODE -ne 0) {
            throw "wrangler deploy failed."
        }
    }

    if (-not $SkipSecrets) {
        if (-not $DeviceId) {
            throw "DeviceId is required unless -SkipSecrets is used."
        }
        Set-WorkerSecret "PHONE_DEVICE_ID" $DeviceId

        if ($OwnerToken) {
            Set-WorkerSecret "PHONE_OWNER_TOKEN" $OwnerToken
        } else {
            Write-Host "OwnerToken was not provided. Worker will restrict device id if PHONE_DEVICE_ID is set, but phone WebSocket token will not be pinned."
        }
    }

    Write-Host "After deploy, configure the Android phone with:"
    Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\configure-phone-relay.ps1 -RelayBaseUrl `"https://<worker-name>.<account>.workers.dev`" -DeviceId `"$DeviceId`""
    Write-Host "Public MCP URL format:"
    Write-Host "https://<worker-name>.<account>.workers.dev/d/$DeviceId/mcp"
    if ($Temporary) {
        Write-Host "Temporary deploy note:"
        Write-Host "Use the preview URL printed by Wrangler as RelayBaseUrl. This is for testing only; run npx wrangler login and deploy without -Temporary for the permanent no-PC relay."
    }
} finally {
    Pop-Location
}
