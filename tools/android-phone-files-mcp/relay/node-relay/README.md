# Node Relay

Self-hosted relay for Android Phone Files MCP.

The Android app opens an outbound WebSocket to:

```text
wss://<relay-host>/__phone_ws/<device-id>
```

The MCP client connects to:

```text
https://<relay-host>/d/<device-id>/mcp
```

## Run

```powershell
npm install
npm start
```

## Environment

```text
PORT=8788
PHONE_DEVICE_ID=phone-example
PHONE_OWNER_TOKEN=<owner-token>
```

Use `relay.env.example` as a template. Do not commit a real `.env` file.

