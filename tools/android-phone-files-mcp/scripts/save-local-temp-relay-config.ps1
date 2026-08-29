param(
    [Parameter(Mandatory = $true)]
    [string]$OwnerToken,

    [string]$DeviceId = "phone-example",
    [int]$RelayPort = 8788,
    [string]$CloudflaredPath = "",
    [string]$AdbPath = "adb.exe",
    [switch]$AutoConfigurePhone,
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
if (-not $CloudflaredPath) {
    $CloudflaredPath = Join-Path $ProjectRoot "tools\cloudflared.exe"
}
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ProjectRoot "runtime\local-temp-relay.env"
}

function Assert-NoNewline([string]$Name, [string]$Value) {
    if ($Value -match "[`r`n]") {
        throw "$Name must not contain newline characters."
    }
}

Assert-NoNewline "OwnerToken" $OwnerToken
Assert-NoNewline "DeviceId" $DeviceId
Assert-NoNewline "CloudflaredPath" $CloudflaredPath
Assert-NoNewline "AdbPath" $AdbPath

$configDir = Split-Path -Parent $ConfigPath
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$content = @(
    "DEVICE_ID=$DeviceId",
    "OWNER_TOKEN=$OwnerToken",
    "RELAY_PORT=$RelayPort",
    "CLOUDFLARED_PATH=$CloudflaredPath",
    "ADB_PATH=$AdbPath",
    "AUTO_CONFIGURE_PHONE=$($AutoConfigurePhone.IsPresent.ToString().ToLowerInvariant())"
) -join "`n"
[System.IO.File]::WriteAllText($ConfigPath, $content + "`n", [System.Text.UTF8Encoding]::new($false))

try {
    $acl = Get-Acl -LiteralPath $ConfigPath
    $acl.SetAccessRuleProtection($true, $false)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rules = @(
        (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $currentUser, "FullControl", "Allow"),
        (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList "BUILTIN\Administrators", "FullControl", "Allow")
    )
    foreach ($rule in $rules) {
        $acl.AddAccessRule($rule) | Out-Null
    }
    Set-Acl -LiteralPath $ConfigPath -AclObject $acl
} catch {
    Write-Host "Config saved, but ACL hardening failed: $($_.Exception.Message)"
}

Write-Host "Local temporary relay config saved:"
Write-Host $ConfigPath
Write-Host "This file contains the owner token. Do not share it."
if ($AutoConfigurePhone) {
    Write-Host "Phone auto-config is enabled when the local temporary relay starts and ADB is connected."
}
