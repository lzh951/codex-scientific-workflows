param(
    [Parameter(Mandatory = $true)]
    [string]$SshHost,

    [string]$SshUser = "root",
    [string]$RemoteDir = "/opt/devspace-phone-relay",
    [string]$Domain = "",
    [string]$RelayBaseUrl = "",
    [string]$DeviceId = "phone-example",
    [string]$OwnerToken = "",
    [switch]$SkipCaddy
)

$ErrorActionPreference = "Stop"
if ($Domain) {
    if ($Domain -match "^https?://") {
        throw "Pass -Domain as a host name only, for example relay.example.com, not https://relay.example.com"
    }
    if ($Domain -notmatch "^[A-Za-z0-9.-]+$") {
        throw "Unsupported domain value: $Domain"
    }
}
$RelayDir = Resolve-Path "$PSScriptRoot\..\relay\node-relay"
$Archive = Join-Path ([System.IO.Path]::GetTempPath()) "devspace-phone-relay.zip"
Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue

$Staging = Join-Path ([System.IO.Path]::GetTempPath()) "devspace-phone-relay-package"
Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
Copy-Item -LiteralPath (Join-Path $RelayDir "server.js") -Destination $Staging
Copy-Item -LiteralPath (Join-Path $RelayDir "package.json") -Destination $Staging
Copy-Item -LiteralPath (Join-Path $RelayDir "package-lock.json") -Destination $Staging
Copy-Item -LiteralPath (Join-Path $RelayDir "Dockerfile") -Destination $Staging
Copy-Item -LiteralPath (Join-Path $RelayDir "docker-compose.yml") -Destination $Staging
Copy-Item -LiteralPath (Join-Path $RelayDir "systemd") -Destination $Staging -Recurse
Copy-Item -LiteralPath (Join-Path $RelayDir "caddy") -Destination $Staging -Recurse
Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $Archive -Force

$Target = "$SshUser@$SshHost"
Write-Host "Uploading relay package to ${Target}:$RemoteDir"
ssh $Target "mkdir -p $RemoteDir"
scp $Archive "${Target}:/tmp/devspace-phone-relay.zip"

Write-Host "Installing Node relay on VPS..."
$relayEnvLines = @("PORT=8788")
if ($DeviceId) {
    $relayEnvLines += "PHONE_DEVICE_ID=$DeviceId"
}
if ($OwnerToken) {
    $relayEnvLines += "PHONE_OWNER_TOKEN=$OwnerToken"
} else {
    Write-Host "Owner token was not provided. Relay will not enforce a fixed phone token; pass -OwnerToken to harden the VPS relay."
}
$relayEnv = ($relayEnvLines -join "`n") + "`n"
$relayEnvLocal = Join-Path ([System.IO.Path]::GetTempPath()) "devspace-phone-relay.env"
[System.IO.File]::WriteAllText($relayEnvLocal, $relayEnv, [System.Text.UTF8Encoding]::new($false))
scp $relayEnvLocal "${Target}:/tmp/devspace-phone-relay.env"

ssh $Target @"
set -e
mkdir -p '$RemoteDir'
cd '$RemoteDir'
if command -v unzip >/dev/null 2>&1; then unzip -o /tmp/devspace-phone-relay.zip; else python3 -m zipfile -e /tmp/devspace-phone-relay.zip .; fi
cp /tmp/devspace-phone-relay.env relay.env
chmod 600 relay.env
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose up -d --build
else
  id devspace >/dev/null 2>&1 || useradd --system --home '$RemoteDir' --shell /usr/sbin/nologin devspace
  command -v node >/dev/null 2>&1 || (apt-get update && apt-get install -y nodejs npm)
  npm ci --omit=dev
  cp systemd/devspace-phone-relay.service /etc/systemd/system/devspace-phone-relay.service 2>/dev/null || true
  if [ ! -f /etc/systemd/system/devspace-phone-relay.service ]; then
    cat >/etc/systemd/system/devspace-phone-relay.service <<'SERVICE'
[Unit]
Description=DevSpace Android phone-direct relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/devspace-phone-relay
Environment=PORT=8788
ExecStart=/usr/bin/node /opt/devspace-phone-relay/server.js
Restart=always
RestartSec=3
User=devspace
Group=devspace
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE
  fi
  systemctl daemon-reload
  systemctl enable --now devspace-phone-relay
fi
"@

if ($Domain -and -not $SkipCaddy) {
    Write-Host "Configuring Caddy reverse proxy for https://$Domain -> 127.0.0.1:8788"
    ssh $Target @"
set -e
if ! command -v caddy >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y caddy
  else
    echo 'Caddy is not installed and this script only auto-installs it on apt-based Linux.'
    exit 12
  fi
fi
mkdir -p /etc/caddy/conf.d
if [ -f /etc/caddy/Caddyfile ]; then
  cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-devspace-phone-relay-\$(date +%Y%m%d%H%M%S)
else
  touch /etc/caddy/Caddyfile
fi
if ! grep -q 'import /etc/caddy/conf.d/\*.caddy' /etc/caddy/Caddyfile; then
  printf '\nimport /etc/caddy/conf.d/*.caddy\n' >> /etc/caddy/Caddyfile
fi
cat >/etc/caddy/conf.d/devspace-phone-relay.caddy <<'CADDY'
$Domain {
    reverse_proxy 127.0.0.1:8788
}
CADDY
caddy validate --config /etc/caddy/Caddyfile
systemctl enable --now caddy
systemctl reload caddy || systemctl restart caddy
"@
} elseif ($Domain) {
    Write-Host "Domain requested: $Domain"
    Write-Host "Caddy configuration skipped. Reverse proxy https://$Domain to 127.0.0.1:8788 manually."
}

if (-not $RelayBaseUrl) {
    if ($Domain) {
        $RelayBaseUrl = "https://$Domain"
    } else {
        $RelayBaseUrl = "http://$SshHost:8788"
    }
}

Write-Host "Relay base URL to put into Android app:"
Write-Host $RelayBaseUrl
Write-Host "Public MCP URL format:"
Write-Host "$RelayBaseUrl/d/$DeviceId/mcp"
Write-Host "Configure the connected Android phone with:"
Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\configure-phone-relay.ps1 -RelayBaseUrl `"$RelayBaseUrl`" -DeviceId `"$DeviceId`""
