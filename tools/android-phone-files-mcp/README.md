# Android Phone Files MCP

Android Phone Files MCP is a prototype bridge that lets an MCP client, such as ChatGPT custom apps, access files in explicitly authorized Android storage.

It is meant for personal-device file workflows, not full phone control.

## What It Provides

- Android app with a phone-local MCP HTTP endpoint on port `7676`
- Owner-token based authorization for MCP access
- File tools for listing, reading, writing, hashing, searching, zipping, and chunked transfer
- Text helpers for automatic charset detection, bounded line reads, previews, and literal edits with backups
- Short-lived HTTPS download links for individual phone files through the configured relay
- Optional outbound phone relay mode for public HTTPS access
- Node.js relay for VPS or local temporary tunnel use
- Cloudflare Worker relay option using Durable Objects
- PowerShell helpers for ADB install, relay configuration, smoke tests, and file transfer

## Security Boundary

The intended file root is Android shared storage, normally:

```text
/storage/emulated/0
```

Do not present this as system-wide phone access. The app should not be used to expose private app databases, messages, contacts, system partitions, or other app-private data.

The `run_shell` MCP tool is kept only as a compatibility response and is intentionally disabled in this Android build.

## Typical Public MCP URL

```text
https://<relay-host>/d/<device-id>/mcp
```

Use placeholders in documentation and examples. Never publish a real device ID, real owner token, or live public relay URL.

## Build

Requirements:

- JDK 17
- Android SDK / Gradle with Android Gradle Plugin support
- Android device with USB debugging enabled for install/configuration scripts

From this directory:

```powershell
gradle :app:assembleDebug
```

If your workspace path contains non-ASCII characters and Android build tools fail, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-android-ascii.ps1
```

## Install And Start

After building the debug APK:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-phone-direct-manual.ps1 -RelayBaseUrl "https://relay.example.com" -DeviceId "phone-example"
```

The script installs the APK, grants available file/media/power permissions through ADB where possible, starts the foreground MCP service, configures relay mode, and prints the public MCP URL.

## Local Temporary Relay

For testing, a computer can run the Node relay and expose it with a temporary tunnel:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-local-temp-relay.ps1 -DeviceId "phone-example" -OwnerToken "<owner-token>"
```

Temporary `trycloudflare.com` URLs can change after restarts. For stable use, deploy the Node relay or Worker relay behind a fixed hostname.

## Temporary Download Links

The Android MCP server can create short-lived public download URLs for files inside the authorized storage root:

```text
https://<relay-host>/d/<device-id>/download/<download-token>
```

The default lifetime is 1 hour and the maximum lifetime is 1 hour. Links are bearer URLs: anyone with the URL can download that one file until the link expires or is revoked. This relay path buffers one file response through the phone WebSocket relay; the default safe per-response cap is 23 MiB to stay below Cloudflare Durable Object WebSocket message limits after base64/JSON overhead.

Use this for moving a selected phone file into a ChatGPT conversation or another trusted client. Do not publish generated download URLs in issues, logs, screenshots, examples, or documentation.

## Node Relay

```powershell
cd .\relay\node-relay
npm install
npm start
```

Environment variables:

```text
PORT=8788
PHONE_DEVICE_ID=phone-example
PHONE_OWNER_TOKEN=<owner-token>
```

## Cloudflare Worker Relay

```powershell
cd .\relay\cloudflare-worker
npx wrangler login
npx wrangler deploy
```

Set Worker secrets:

```text
PHONE_DEVICE_ID=phone-example
PHONE_OWNER_TOKEN=<owner-token>
```

## Smoke Test

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mcp-smoke-test.ps1 -OwnerToken "<owner-token>" -McpUrl "https://relay.example.com/d/phone-example/mcp"
```

## Included MCP Tools

- `open_workspace`
- `list_roots`
- `read_file`
- `read_file_auto`
- `read_lines`
- `file_preview`
- `edit_file`
- `create_download_link`
- `revoke_download_link`
- `write_file`
- `read_file_base64`
- `write_file_base64`
- `read_file_chunk_base64`
- `write_file_chunk_base64`
- `hash_file`
- `list_directory`
- `find_files`
- `grep_files`
- `stat_path`
- `make_directory`
- `delete_path`
- `move_path`
- `copy_path`
- `zip_paths`
- `unzip_file`
- `scan_media`

## Do Not Commit

- Owner tokens
- Real device IDs
- Live relay URLs
- Generated download URLs or download tokens
- APK build outputs
- screenshots containing tokens or URLs
- logs
- `node_modules`
- `runtime`
- `.env` files
