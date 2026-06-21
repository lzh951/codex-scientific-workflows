package com.lzh.devspaceandroid;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ConnectException;
import java.net.HttpURLConnection;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

final class RelayClient {
    private static final int MAX_BODY_BYTES = 10 * 1024 * 1024;
    private static RelayClient instance;

    private final Context context;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor requestExecutor = new ThreadPoolExecutor(
        1,
        4,
        30L,
        TimeUnit.SECONDS,
        new ArrayBlockingQueue<Runnable>(16),
        new ThreadFactory() {
            private final AtomicInteger counter = new AtomicInteger();

            @Override
            public Thread newThread(Runnable runnable) {
                return new Thread(runnable, "devspace-relay-request-" + counter.incrementAndGet());
            }
        }
    );
    private final OkHttpClient client = new OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .pingInterval(25, TimeUnit.SECONDS)
        .build();

    private volatile WebSocket socket;
    private volatile boolean shouldRun;
    private volatile String status = "stopped";
    private volatile String lastMessage = "Relay is stopped.";

    private RelayClient(Context context) {
        this.context = context.getApplicationContext();
    }

    static synchronized RelayClient get(Context context) {
        if (instance == null) {
            instance = new RelayClient(context);
        }
        return instance;
    }

    synchronized void start() {
        String ownerToken = new TokenStore(context).getOwnerToken();
        String wsUrl = RelayConfig.webSocketUrl(context);
        if (wsUrl.isEmpty()) {
            shouldRun = false;
            status = "missing relay URL";
            lastMessage = "Set the relay base URL before starting phone-direct mode.";
            return;
        }
        if (socket != null) {
            shouldRun = true;
            return;
        }
        shouldRun = true;
        status = "connecting";
        lastMessage = "Connecting to relay.";
        Request request = new Request.Builder()
            .url(wsUrl)
            .header("Authorization", "Bearer " + ownerToken)
            .build();
        socket = client.newWebSocket(request, new Listener());
    }

    synchronized void restart() {
        WebSocket current = socket;
        socket = null;
        if (current != null) {
            current.close(1000, "restarting");
        }
        start();
    }

    synchronized void stop() {
        shouldRun = false;
        WebSocket current = socket;
        socket = null;
        if (current != null) {
            current.close(1000, "stopped");
        }
        status = "stopped";
        lastMessage = "Relay is stopped.";
    }

    boolean isRunning() {
        return socket != null && shouldRun;
    }

    String statusLine() {
        return "Relay status: " + status;
    }

    String lastMessage() {
        return lastMessage;
    }

    private void reconnectLater(WebSocket webSocket) {
        synchronized (this) {
            if (socket != webSocket) {
                return;
            }
            socket = null;
        }
        if (!shouldRun) {
            status = "stopped";
            return;
        }
        status = "reconnecting";
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (shouldRun && socket == null) {
                    start();
                }
            }
        }, 5000L);
    }

    private final class Listener extends WebSocketListener {
        @Override
        public void onOpen(WebSocket webSocket, Response response) {
            if (socket != webSocket) {
                return;
            }
            status = "connected";
            lastMessage = "Relay connected. Public MCP URL: " + RelayConfig.publicMcpUrl(context);
        }

        @Override
        public void onMessage(WebSocket webSocket, String text) {
            handleMessage(webSocket, text);
        }

        @Override
        public void onClosing(WebSocket webSocket, int code, String reason) {
            webSocket.close(code, reason);
        }

        @Override
        public void onClosed(WebSocket webSocket, int code, String reason) {
            lastMessage = "Relay closed: " + reason;
            reconnectLater(webSocket);
        }

        @Override
        public void onFailure(WebSocket webSocket, Throwable error, Response response) {
            lastMessage = "Relay error: " + (error.getMessage() == null ? error.toString() : error.getMessage());
            reconnectLater(webSocket);
        }
    }

    private void handleMessage(WebSocket webSocket, String text) {
        try {
            JSONObject request = new JSONObject(text);
            String id = request.optString("id", "");
            try {
                requestExecutor.execute(new Runnable() {
                    @Override
                    public void run() {
                        proxyRequest(webSocket, id, request);
                    }
                });
            } catch (RejectedExecutionException rejected) {
                sendError(webSocket, id, "phone relay is busy; retry later");
            }
        } catch (Exception error) {
            lastMessage = "Bad relay message: " + safeMessage(error);
        }
    }

    private void proxyRequest(WebSocket webSocket, String id, JSONObject request) {
        HttpURLConnection connection = null;
        try {
            String method = request.optString("method", "GET");
            String path = request.optString("path", "/");
            if (!path.startsWith("/")) {
                path = "/" + path;
            }
            URL url = new URL("http://127.0.0.1:" + McpServer.PORT + path);
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(60000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod(method);
            applyHeaders(connection, request.optJSONObject("headers"));
            byte[] body = decode(request.optString("bodyBase64", ""));
            if (body.length > 0 || allowsRequestBody(method)) {
                connection.setDoOutput(true);
                if (body.length > 0) {
                    OutputStream output = connection.getOutputStream();
                    output.write(body);
                    output.close();
                }
            }
            int statusCode = connection.getResponseCode();
            InputStream input = statusCode >= 400 ? connection.getErrorStream() : connection.getInputStream();
            byte[] responseBody = readAll(input);
            JSONObject response = new JSONObject()
                .put("id", id)
                .put("status", statusCode)
                .put("headers", responseHeaders(connection))
                .put("bodyBase64", encode(responseBody));
            webSocket.send(response.toString());
            lastMessage = "Proxied " + method + " " + path + " -> " + statusCode;
        } catch (Exception error) {
            sendError(webSocket, id, safeMessage(error));
            if (shouldRestartMcp(error)) {
                PhoneMcpService.requestServerRestart(context, "relay proxy error: " + safeMessage(error));
            }
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private void applyHeaders(HttpURLConnection connection, JSONObject headers) throws JSONException {
        if (headers == null) {
            return;
        }
        Iterator<String> keys = headers.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            if (skipRequestHeader(key)) {
                continue;
            }
            connection.setRequestProperty(key, headers.optString(key, ""));
        }
    }

    private boolean skipRequestHeader(String key) {
        String lower = key == null ? "" : key.toLowerCase();
        return "host".equals(lower)
            || "connection".equals(lower)
            || "content-length".equals(lower)
            || "accept-encoding".equals(lower);
    }

    private JSONObject responseHeaders(HttpURLConnection connection) throws JSONException {
        JSONObject headers = new JSONObject();
        for (Map.Entry<String, List<String>> entry : connection.getHeaderFields().entrySet()) {
            if (entry.getKey() == null || entry.getValue() == null || entry.getValue().isEmpty()) {
                continue;
            }
            if (!"content-length".equalsIgnoreCase(entry.getKey())
                && !"transfer-encoding".equalsIgnoreCase(entry.getKey())
                && !"connection".equalsIgnoreCase(entry.getKey())) {
                headers.put(entry.getKey(), entry.getValue().get(0));
            }
        }
        return headers;
    }

    private boolean allowsRequestBody(String method) {
        return "POST".equalsIgnoreCase(method)
            || "PUT".equalsIgnoreCase(method)
            || "PATCH".equalsIgnoreCase(method);
    }

    private byte[] readAll(InputStream input) throws Exception {
        if (input == null) {
            return new byte[0];
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int total = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            total += read;
            if (total > MAX_BODY_BYTES) {
                throw new IllegalStateException("Relay response is larger than " + MAX_BODY_BYTES + " bytes.");
            }
            output.write(buffer, 0, read);
        }
        input.close();
        return output.toByteArray();
    }

    private void sendError(WebSocket webSocket, String id, String message) {
        try {
            JSONObject response = new JSONObject()
                .put("id", id)
                .put("status", 502)
                .put("headers", new JSONObject().put("content-type", "text/plain; charset=utf-8"))
                .put("bodyBase64", encode(("Relay error: " + message).getBytes(StandardCharsets.UTF_8)));
            webSocket.send(response.toString());
            lastMessage = "Relay proxy error: " + message;
        } catch (Exception ignored) {
        }
    }

    private byte[] decode(String value) {
        if (value == null || value.isEmpty()) {
            return new byte[0];
        }
        return Base64.decode(value, Base64.NO_WRAP);
    }

    private String encode(byte[] value) {
        return Base64.encodeToString(value, Base64.NO_WRAP);
    }

    private String safeMessage(Exception error) {
        String message = error.getMessage();
        return message == null ? error.toString() : message;
    }

    private boolean shouldRestartMcp(Exception error) {
        Throwable current = error;
        while (current != null) {
            if (current instanceof SocketTimeoutException
                || current instanceof ConnectException
                || current instanceof SocketException) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }
}
