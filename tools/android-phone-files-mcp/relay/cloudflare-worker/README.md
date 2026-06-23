# Cloudflare Worker Relay

Cloudflare Worker relay for Android Phone Files MCP.

The phone connects to:

```text
wss://<worker-host>/__phone_ws/<device-id>
```

The MCP client connects to:

```text
https://<worker-host>/d/<device-id>/mcp
```

## Deploy

```powershell
npx wrangler login
npx wrangler deploy
```

Set Worker secrets:

```text
PHONE_DEVICE_ID=phone-example
PHONE_OWNER_TOKEN=<owner-token>
```

Do not publish real Worker secrets, real device IDs, or live public MCP URLs.
