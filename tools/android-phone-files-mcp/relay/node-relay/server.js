import http from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer } from "ws";

const port = Number(process.env.PORT || 8788);
const allowedDeviceId = (process.env.PHONE_DEVICE_ID || process.env.DEVSPACE_DEVICE_ID || "").trim();
const allowedOwnerToken = (process.env.PHONE_OWNER_TOKEN || process.env.DEVSPACE_OWNER_TOKEN || "").trim();
const devices = new Map();

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://${request.headers.host || "127.0.0.1"}`);
    if (url.pathname === "/healthz") {
      send(response, 200, { "content-type": "application/json" }, JSON.stringify({ ok: true, name: "devspace-node-relay" }));
      return;
    }
    if (!url.pathname.startsWith("/d/")) {
      send(response, 200, { "content-type": "text/plain; charset=utf-8" }, "DevSpace node relay is running.\nUse /d/<device-id>/mcp as the public MCP URL.\n");
      return;
    }
    const parts = url.pathname.split("/").filter(Boolean);
    const deviceId = parts[1] || "";
    if (!isAllowedDevice(deviceId)) {
      send(response, 404, { "content-type": "text/plain; charset=utf-8" }, "Unknown device.");
      return;
    }
    const device = devices.get(deviceId);
    if (!device || device.socket.readyState !== device.socket.OPEN) {
      send(response, 503, { "content-type": "text/plain; charset=utf-8" }, "Phone is not connected to this relay.");
      return;
    }
    const strippedPath = "/" + parts.slice(2).join("/");
    const body = await readRequestBody(request);
    const id = randomUUID();
    const payload = {
      id,
      method: request.method,
      path: (strippedPath === "/" ? "/" : strippedPath) + url.search,
      headers: forwardedHeaders(request, deviceId),
      bodyBase64: body.toString("base64"),
    };
    const phoneResponse = await requestPhone(device, id, payload);
    response.writeHead(phoneResponse.status || 502, phoneResponse.headers || {});
    response.end(Buffer.from(phoneResponse.bodyBase64 || "", "base64"));
  } catch (error) {
    send(response, 502, { "content-type": "text/plain; charset=utf-8" }, `Relay error: ${error.message || error}`);
  }
});

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host || "127.0.0.1"}`);
  if (!url.pathname.startsWith("/__phone_ws/")) {
    socket.destroy();
    return;
  }
  const deviceId = url.pathname.split("/").filter(Boolean)[1] || "";
  const token = phoneToken(request, url);
  if (!deviceId || !token || !isAllowedDevice(deviceId) || !isAllowedPhoneToken(token)) {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(request, socket, head, (ws) => {
    const existing = devices.get(deviceId);
    if (existing && existing.token && existing.token !== token && existing.socket.readyState === existing.socket.OPEN) {
      ws.close(1008, "A phone is already connected for this device.");
      return;
    }
    if (existing && existing.socket.readyState === existing.socket.OPEN) {
      existing.socket.close(1012, "Replaced by a newer phone connection.");
    }
    const device = { socket: ws, token, pending: new Map() };
    devices.set(deviceId, device);
    ws.on("message", (data) => handlePhoneMessage(device, data));
    ws.on("close", () => {
      if (devices.get(deviceId) === device) {
        devices.delete(deviceId);
      }
    });
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`DevSpace node relay listening on http://127.0.0.1:${port}`);
  if (allowedDeviceId) {
    console.log(`DevSpace node relay restricted to device ${allowedDeviceId}`);
  }
  if (allowedOwnerToken) {
    console.log("DevSpace node relay requires the configured phone owner token for WebSocket connections");
  }
});

function handlePhoneMessage(device, data) {
  let message;
  try {
    message = JSON.parse(data.toString());
  } catch {
    return;
  }
  const pending = device.pending.get(message.id);
  if (!pending) {
    return;
  }
  clearTimeout(pending.timer);
  device.pending.delete(message.id);
  pending.resolve(message);
}

function requestPhone(device, id, payload) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      device.pending.delete(id);
      reject(new Error("Timed out waiting for phone response."));
    }, 60000);
    device.pending.set(id, { resolve, reject, timer });
    device.socket.send(JSON.stringify(payload), (error) => {
      if (error) {
        clearTimeout(timer);
        device.pending.delete(id);
        reject(error);
      }
    });
  });
}

function forwardedHeaders(request, deviceId) {
  const headers = { ...request.headers };
  delete headers.host;
  delete headers.connection;
  delete headers["content-length"];
  headers["x-forwarded-host"] = request.headers.host || "";
  headers["x-forwarded-proto"] = "https";
  headers["x-forwarded-prefix"] = `/d/${deviceId}`;
  return headers;
}

function phoneToken(request, url) {
  const authorization = request.headers.authorization || "";
  const prefix = "bearer ";
  if (authorization.toLowerCase().startsWith(prefix)) {
    return authorization.slice(prefix.length).trim();
  }
  return url.searchParams.get("token") || "";
}

function isAllowedDevice(deviceId) {
  return !allowedDeviceId || deviceId === allowedDeviceId;
}

function isAllowedPhoneToken(token) {
  return !allowedOwnerToken || token === allowedOwnerToken;
}

function readRequestBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}

function send(response, status, headers, body) {
  response.writeHead(status, headers);
  response.end(body);
}
