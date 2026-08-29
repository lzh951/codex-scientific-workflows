package com.lzh.devspaceandroid;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.PowerManager;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public final class PhoneMcpService extends Service {
    static final String ACTION_START = "com.lzh.devspaceandroid.START";
    static final String ACTION_STOP = "com.lzh.devspaceandroid.STOP";
    static final String ACTION_START_RELAY = "com.lzh.devspaceandroid.START_RELAY";
    static final String ACTION_STOP_RELAY = "com.lzh.devspaceandroid.STOP_RELAY";
    static final String ACTION_RESTART_SERVER = "com.lzh.devspaceandroid.RESTART_SERVER";
    static final String EXTRA_RELAY_BASE_URL = "relay_base_url";
    static final String EXTRA_RELAY_DEVICE_ID = "relay_device_id";
    static final String EXTRA_RESTART_REASON = "restart_reason";
    private static final String CHANNEL_ID = "devspace_android_server";
    private static final long WATCHDOG_FIRST_DELAY_MS = 20_000L;
    private static final long WATCHDOG_INTERVAL_MS = 15_000L;
    private static final int WATCHDOG_TIMEOUT_MS = 5_000;
    private static volatile boolean running;
    private static volatile boolean powerLocksHeld;
    private static volatile boolean relayRequested;
    private static volatile String watchdogStatus = "not started";
    private static volatile long lastWatchdogOkAt;
    private static volatile int watchdogRestartCount;
    private McpServer server;
    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;
    private ConnectivityManager.NetworkCallback networkCallback;
    private HandlerThread watchdogThread;
    private Handler watchdogHandler;
    private final Runnable watchdogRunnable = new Runnable() {
        @Override
        public void run() {
            runWatchdogCheck();
        }
    };

    static boolean isRunning() {
        return running;
    }

    static boolean arePowerLocksHeld() {
        return powerLocksHeld;
    }

    static String watchdogStatus() {
        return watchdogStatus;
    }

    static long lastWatchdogOkAt() {
        return lastWatchdogOkAt;
    }

    static int watchdogRestartCount() {
        return watchdogRestartCount;
    }

    static void start(Context context) {
        Intent intent = new Intent(context, PhoneMcpService.class).setAction(ACTION_START);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    static void stop(Context context) {
        context.startService(new Intent(context, PhoneMcpService.class).setAction(ACTION_STOP));
    }

    static void startRelay(Context context) {
        Intent intent = new Intent(context, PhoneMcpService.class).setAction(ACTION_START_RELAY);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    static void stopRelay(Context context) {
        context.startService(new Intent(context, PhoneMcpService.class).setAction(ACTION_STOP_RELAY));
    }

    static void requestServerRestart(Context context, String reason) {
        Intent intent = new Intent(context, PhoneMcpService.class)
            .setAction(ACTION_RESTART_SERVER)
            .putExtra(EXTRA_RESTART_REASON, reason == null ? "requested" : reason);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        boolean stickyRestart = intent == null;
        String action = stickyRestart ? ACTION_START : intent.getAction();
        if (intent != null && intent.hasExtra(EXTRA_RELAY_BASE_URL)) {
            RelayConfig.setRelayBaseUrl(this, intent.getStringExtra(EXTRA_RELAY_BASE_URL));
        }
        if (intent != null && intent.hasExtra(EXTRA_RELAY_DEVICE_ID)) {
            RelayConfig.setDeviceId(this, intent.getStringExtra(EXTRA_RELAY_DEVICE_ID));
        }
        if (ACTION_STOP.equals(action)) {
            relayRequested = false;
            RelayConfig.setRelayEnabled(this, false);
            RelayClient.get(this).stop();
            stopServer();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }
        if (ACTION_STOP_RELAY.equals(action)) {
            relayRequested = false;
            RelayConfig.setRelayEnabled(this, false);
            RelayClient.get(this).stop();
            return START_STICKY;
        }
        startForeground(7, notification());
        if (ACTION_RESTART_SERVER.equals(action)) {
            restartServerFromWatchdog(intent == null ? "requested" : intent.getStringExtra(EXTRA_RESTART_REASON));
            return START_STICKY;
        }
        startServer();
        if (ACTION_START_RELAY.equals(action)) {
            relayRequested = true;
            RelayConfig.setRelayEnabled(this, true);
            RelayClient.get(this).restart();
        } else if ((stickyRestart || ACTION_START.equals(action)) && RelayConfig.isRelayEnabled(this)) {
            relayRequested = true;
            RelayClient.get(this).start();
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        RelayClient.get(this).stop();
        stopServer();
        super.onDestroy();
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        if (!RelayConfig.getRelayBaseUrl(this).isEmpty()) {
            startRelay(this);
        }
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void startServer() {
        if (server != null) {
            return;
        }
        server = new McpServer(this);
        try {
            server.start(10_000, false);
            running = true;
            acquireRuntimeLocks();
            startNetworkCallback();
            startWatchdog();
        } catch (IOException error) {
            running = false;
            server = null;
            throw new IllegalStateException("Could not start MCP server", error);
        }
    }

    private void stopServer() {
        stopWatchdog();
        stopNetworkCallback();
        if (server != null) {
            server.stop();
            server = null;
        }
        releaseRuntimeLocks();
        running = false;
    }

    private synchronized void startWatchdog() {
        if (watchdogHandler != null) {
            return;
        }
        watchdogThread = new HandlerThread("devspace-mcp-watchdog");
        watchdogThread.start();
        watchdogHandler = new Handler(watchdogThread.getLooper());
        watchdogStatus = "started";
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_FIRST_DELAY_MS);
    }

    private synchronized void stopWatchdog() {
        if (watchdogHandler != null) {
            watchdogHandler.removeCallbacksAndMessages(null);
            watchdogHandler = null;
        }
        if (watchdogThread != null) {
            watchdogThread.quitSafely();
            watchdogThread = null;
        }
        watchdogStatus = "stopped";
    }

    private void runWatchdogCheck() {
        try {
            if (server == null || !running) {
                watchdogStatus = "server not running";
                restartServerFromWatchdog("server not running");
            } else if (probeLocalHealth()) {
                lastWatchdogOkAt = System.currentTimeMillis();
                watchdogStatus = "healthy";
            } else {
                watchdogStatus = "health check failed";
                restartServerFromWatchdog("health check failed");
            }
            ensureRelayRunningFromWatchdog();
        } catch (RuntimeException error) {
            watchdogStatus = "watchdog error: " + safeMessage(error);
            restartServerFromWatchdog("watchdog error");
        } finally {
            Handler handler = watchdogHandler;
            if (handler != null) {
                handler.postDelayed(watchdogRunnable, WATCHDOG_INTERVAL_MS);
            }
        }
    }

    private void ensureRelayRunningFromWatchdog() {
        if (!relayRequested || RelayConfig.getRelayBaseUrl(this).isEmpty()) {
            return;
        }
        RelayClient relayClient = RelayClient.get(this);
        if (!relayClient.isRunning()) {
            relayClient.start();
            watchdogStatus = watchdogStatus + "; relay restart requested";
        } else if (!probePublicRelayHealth()) {
            relayClient.stop();
            relayClient.start();
            watchdogStatus = watchdogStatus + "; relay public probe failed; relay reconnected";
        }
    }

    private synchronized void startNetworkCallback() {
        if (networkCallback != null) {
            return;
        }
        ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
        if (connectivityManager == null) {
            return;
        }
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                if (relayRequested) {
                    watchdogStatus = "network available; relay checked";
                    RelayClient.get(PhoneMcpService.this).start();
                }
            }

            @Override
            public void onLost(Network network) {
                if (relayRequested) {
                    watchdogStatus = "network lost; relay reconnect pending";
                }
            }
        };
        try {
            NetworkRequest request = new NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build();
            connectivityManager.registerNetworkCallback(request, networkCallback);
        } catch (RuntimeException error) {
            networkCallback = null;
        }
    }

    private synchronized void stopNetworkCallback() {
        if (networkCallback == null) {
            return;
        }
        ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
        if (connectivityManager != null) {
            try {
                connectivityManager.unregisterNetworkCallback(networkCallback);
            } catch (RuntimeException ignored) {
            }
        }
        networkCallback = null;
    }

    private boolean probeLocalHealth() {
        HttpURLConnection connection = null;
        try {
            URL url = new URL("http://127.0.0.1:" + McpServer.PORT + "/healthz");
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(WATCHDOG_TIMEOUT_MS);
            connection.setReadTimeout(WATCHDOG_TIMEOUT_MS);
            connection.setRequestMethod("GET");
            int statusCode = connection.getResponseCode();
            InputStream input = statusCode >= 400 ? connection.getErrorStream() : connection.getInputStream();
            if (input != null) {
                input.close();
            }
            return statusCode == 200;
        } catch (Exception ignored) {
            return false;
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private boolean probePublicRelayHealth() {
        HttpURLConnection connection = null;
        try {
            String base = RelayConfig.getRelayBaseUrl(this);
            if (base.isEmpty()) {
                return false;
            }
            URL url = new URL(base + "/d/" + RelayConfig.getDeviceId(this) + "/healthz");
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(WATCHDOG_TIMEOUT_MS);
            connection.setReadTimeout(WATCHDOG_TIMEOUT_MS);
            connection.setRequestMethod("GET");
            int statusCode = connection.getResponseCode();
            InputStream input = statusCode >= 400 ? connection.getErrorStream() : connection.getInputStream();
            if (input != null) {
                input.close();
            }
            return statusCode == 200;
        } catch (Exception ignored) {
            return false;
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private synchronized void restartServerFromWatchdog(String reason) {
        if (reason == null || reason.isEmpty()) {
            reason = "requested";
        }
        try {
            RelayClient relayClient = RelayClient.get(this);
            if (relayRequested) {
                relayClient.stop();
            }
            if (server != null) {
                server.stop();
                server = null;
            }
            running = false;
            McpServer restarted = new McpServer(this);
            restarted.start(10_000, false);
            server = restarted;
            running = true;
            acquireRuntimeLocks();
            watchdogRestartCount++;
            lastWatchdogOkAt = System.currentTimeMillis();
            watchdogStatus = "restarted after " + reason;
            if (relayRequested) {
                relayClient.start();
            }
        } catch (Exception error) {
            running = false;
            watchdogStatus = "restart failed after " + reason + ": " + safeMessage(error);
        }
    }

    private void acquireRuntimeLocks() {
        try {
            if (wakeLock == null) {
                PowerManager powerManager = (PowerManager) getSystemService(POWER_SERVICE);
                if (powerManager != null) {
                    wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DevSpaceAndroid:McpRelay");
                    wakeLock.setReferenceCounted(false);
                }
            }
            if (wakeLock != null && !wakeLock.isHeld()) {
                wakeLock.acquire();
            }
        } catch (RuntimeException ignored) {
        }

        try {
            if (wifiLock == null) {
                WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
                if (wifiManager != null) {
                    wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "DevSpaceAndroid:WifiRelay");
                    wifiLock.setReferenceCounted(false);
                }
            }
            if (wifiLock != null && !wifiLock.isHeld()) {
                wifiLock.acquire();
            }
        } catch (RuntimeException ignored) {
        }

        powerLocksHeld = (wakeLock != null && wakeLock.isHeld()) || (wifiLock != null && wifiLock.isHeld());
    }

    private void releaseRuntimeLocks() {
        try {
            if (wifiLock != null && wifiLock.isHeld()) {
                wifiLock.release();
            }
        } catch (RuntimeException ignored) {
        }
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        } catch (RuntimeException ignored) {
        }
        powerLocksHeld = false;
    }

    private Notification notification() {
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "DevSpace Android", NotificationManager.IMPORTANCE_LOW);
            manager.createNotificationChannel(channel);
        }
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ? new Notification.Builder(this, CHANNEL_ID)
            : new Notification.Builder(this);
        return builder
            .setContentTitle("DevSpace Android is running")
            .setContentText("MCP server port " + McpServer.PORT + "; relay stays awake for phone-direct mode")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .build();
    }

    private String safeMessage(Exception error) {
        String message = error.getMessage();
        return message == null ? error.toString() : message;
    }
}
