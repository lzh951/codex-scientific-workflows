param(
    [switch]$AlsoStopPortOwner,
    [int]$RelayPort = 8788
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$RuntimeDir = Join-Path $ProjectRoot "runtime"
$NodePidFile = Join-Path $RuntimeDir "local-relay-node.pid"
$CloudflaredPidFile = Join-Path $RuntimeDir "local-relay-cloudflared.pid"

function Stop-FromPidFile([string]$Label, [string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "$Label PID file missing: $Path"
        return
    }
    $pidText = (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Select-Object -First 1)
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $pidText) {
        Write-Host "$Label PID file was empty."
        return
    }
    $process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $process.Id -Force
        Write-Host "$Label stopped: PID $pidText"
    } else {
        Write-Host "$Label PID $pidText was not running."
    }
}

Stop-FromPidFile "Cloudflared" $CloudflaredPidFile
Stop-FromPidFile "Node relay" $NodePidFile

if ($AlsoStopPortOwner) {
    $listeners = Get-NetTCPConnection -LocalPort $RelayPort -State Listen -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -eq "node") {
            Stop-Process -Id $process.Id -Force
            Write-Host "Stopped node process owning port ${RelayPort}: PID $($process.Id)"
        }
    }
}
