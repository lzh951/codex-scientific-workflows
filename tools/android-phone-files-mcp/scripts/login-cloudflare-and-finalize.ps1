param(
    [string]$WorkerDir = "$PSScriptRoot\..\relay\cloudflare-worker",
    [string]$AdbPath = "adb.exe",
    [string]$DeviceId = "",
    [string]$OwnerToken = "",
    [string]$RelayBaseUrl = "",
    [string]$FallbackRelayBaseUrl = "",
    [int]$HostPort = 17676,
    [switch]$SkipLogin,
    [switch]$NoRevertOnFailure,
    [switch]$SkipMcpRoundTrip
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$WorkerDir = (Resolve-Path $WorkerDir).Path
$Finalizer = Join-Path $PSScriptRoot "finalize-cloudflare-worker-phone-direct.ps1"

function Test-WranglerAuthenticated {
    Push-Location $WorkerDir
    try {
        $output = (& npx wrangler whoami 2>&1) -join "`n"
        if ($output -match "not authenticated") {
            return $false
        }
        if ($output -match "You are logged in|Account Name|User") {
            return $true
        }
        return $LASTEXITCODE -eq 0 -and $output -notmatch "not authenticated"
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $Finalizer)) {
    throw "Finalizer not found: $Finalizer"
}

if (-not $SkipLogin -and -not (Test-WranglerAuthenticated)) {
    Write-Host "Cloudflare is not authenticated. Starting Wrangler login."
    Write-Host "A browser window may open. Finish Cloudflare login there, then this script will continue."
    Push-Location $WorkerDir
    try {
        npx wrangler login
        if ($LASTEXITCODE -ne 0) {
            throw "wrangler login failed."
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-WranglerAuthenticated)) {
    throw "Cloudflare is still not authenticated. Run: cd <repo>\tools\android-phone-files-mcp\relay\cloudflare-worker ; npx wrangler login"
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $Finalizer,
    "-AdbPath",
    $AdbPath,
    "-WorkerDir",
    $WorkerDir,
    "-HostPort",
    [string]$HostPort
)
if ($DeviceId) {
    $args += @("-DeviceId", $DeviceId)
}
if ($OwnerToken) {
    $args += @("-OwnerToken", $OwnerToken)
}
if ($RelayBaseUrl) {
    $args += @("-RelayBaseUrl", $RelayBaseUrl)
}
if ($FallbackRelayBaseUrl) {
    $args += @("-FallbackRelayBaseUrl", $FallbackRelayBaseUrl)
}
if ($NoRevertOnFailure) {
    $args += "-NoRevertOnFailure"
}
if ($SkipMcpRoundTrip) {
    $args += "-SkipMcpRoundTrip"
}

Write-Host "Running final Cloudflare Worker phone-direct cutover."
& powershell @args
if ($LASTEXITCODE -ne 0) {
    throw "finalize-cloudflare-worker-phone-direct.ps1 failed."
}
