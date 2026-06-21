export class PhoneTunnel {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.phone = null;
    this.phoneToken = null;
    this.pending = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/__phone_ws/")) {
      return this.acceptPhone(request);
    }
    return this.proxyToPhone(request);
  }

  acceptPhone(request) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected WebSocket upgrade.", { status: 426 });
    }
    const url = new URL(request.url);
    const deviceId = pathPart(url.pathname, 1);
    const token = phoneToken(request, url);
    if (!deviceId || !this.isAllowedDevice(deviceId)) {
      return new Response("Unknown device.", { status: 404 });
    }
    if (!token || !this.isAllowedPhoneToken(token)) {
      return new Response("Missing phone token.", { status: 401 });
    }
    if (this.phone && this.phoneToken && token !== this.phoneToken) {
      return new Response("A phone is already connected for this device.", { status: 403 });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();
    if (this.phone) {
      this.phone.close(1012, "Replaced by a newer phone connection.");
    }
    this.phone = server;
    this.phoneToken = token;
    server.addEventListener("message", (event) => this.onPhoneMessage(event));
    server.addEventListener("close", () => {
      if (this.phone === server) {
        this.phone = null;
      }
    });
    server.addEventListener("error", () => {
      if (this.phone === server) {
        this.phone = null;
      }
    });
    return new Response(null, { status: 101, webSocket: client });
  }

  isAllowedDevice(deviceId) {
    const allowed = (this.env.PHONE_DEVICE_ID || "").trim();
    return !allowed || deviceId === allowed;
  }

  isAllowedPhoneToken(token) {
    const allowed = (this.env.PHONE_OWNER_TOKEN || "").trim();
    return !allowed || token === allowed;
  }

  onPhoneMessage(event) {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (error) {
      return;
    }
    const entry = this.pending.get(message.id);
    if (!entry) {
      return;
    }
    clearTimeout(entry.timer);
    this.pending.delete(message.id);
    entry.resolve(message);
  }

  async proxyToPhone(request) {
    const url = new URL(request.url);
    const prefix = request.headers.get("x-forwarded-prefix") || "";
    const deviceId = prefix.startsWith("/d/") ? prefix.slice(3).split("/")[0] : "";
    if (deviceId && !this.isAllowedDevice(deviceId)) {
      return new Response("Unknown device.", { status: 404 });
    }
    if (!this.phone) {
      return new Response("Phone is not connected to this relay.", { status: 503 });
    }
    const body = await request.arrayBuffer();
    const id = crypto.randomUUID();
    const headers = {};
    request.headers.forEach((value, key) => {
      headers[key] = value;
    });
    const payload = {
      id,
      method: request.method,
      path: url.pathname + url.search,
      headers,
      bodyBase64: arrayBufferToBase64(body),
    };
    const responsePromise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("Timed out waiting for phone response."));
      }, 60000);
      this.pending.set(id, { resolve, reject, timer });
    });
    this.phone.send(JSON.stringify(payload));
    const response = await responsePromise;
    return new Response(base64ToArrayBuffer(response.bodyBase64 || ""), {
      status: response.status || 502,
      headers: response.headers || {},
    });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/healthz") {
      return Response.json({ ok: true, name: "devspace-phone-relay" });
    }
    if (url.pathname.startsWith("/__phone_ws/")) {
      const deviceId = pathPart(url.pathname, 1);
      if (!isAllowedDevice(env, deviceId)) {
        return new Response("Unknown device.", { status: 404 });
      }
      return env.PHONE_TUNNEL.get(env.PHONE_TUNNEL.idFromName(deviceId)).fetch(request);
    }
    if (url.pathname.startsWith("/d/")) {
      const deviceId = pathPart(url.pathname, 1);
      if (!isAllowedDevice(env, deviceId)) {
        return new Response("Unknown device.", { status: 404 });
      }
      const stripped = stripDevicePrefix(url.pathname, deviceId);
      const forwardUrl = new URL(request.url);
      forwardUrl.pathname = stripped;
      const headers = new Headers(request.headers);
      headers.set("x-forwarded-host", url.host);
      headers.set("x-forwarded-proto", "https");
      headers.set("x-forwarded-prefix", "/d/" + deviceId);
      const proxyRequest = new Request(forwardUrl.toString(), {
        method: request.method,
        headers,
        body: request.body,
        redirect: "manual",
      });
      return env.PHONE_TUNNEL.get(env.PHONE_TUNNEL.idFromName(deviceId)).fetch(proxyRequest);
    }
    return new Response(
      "DevSpace phone relay is running.\nUse /d/<device-id>/mcp as the public MCP URL.",
      { status: 200, headers: { "content-type": "text/plain; charset=utf-8" } },
    );
  },
};

function phoneToken(request, url) {
  const authorization = request.headers.get("authorization") || "";
  const prefix = "bearer ";
  if (authorization.toLowerCase().startsWith(prefix)) {
    return authorization.slice(prefix.length).trim();
  }
  return url.searchParams.get("token") || "";
}

function isAllowedDevice(env, deviceId) {
  const allowed = (env.PHONE_DEVICE_ID || "").trim();
  return !allowed || deviceId === allowed;
}

function pathPart(pathname, index) {
  return pathname.split("/").filter(Boolean)[index] || "";
}

function stripDevicePrefix(pathname, deviceId) {
  const prefix = "/d/" + deviceId;
  const stripped = pathname.slice(prefix.length);
  return stripped || "/";
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

function base64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}
