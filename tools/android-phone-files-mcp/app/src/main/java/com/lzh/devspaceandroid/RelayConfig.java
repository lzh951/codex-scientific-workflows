package com.lzh.devspaceandroid;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Locale;
import java.util.UUID;

final class RelayConfig {
    private static final String PREFS = "devspace_android";
    private static final String RELAY_BASE_URL = "relay_base_url";
    private static final String DEVICE_ID = "relay_device_id";
    private static final String RELAY_ENABLED = "relay_enabled";

    private RelayConfig() {
    }

    static String getRelayBaseUrl(Context context) {
        return prefs(context).getString(RELAY_BASE_URL, "");
    }

    static void setRelayBaseUrl(Context context, String value) {
        prefs(context).edit().putString(RELAY_BASE_URL, normalizeBaseUrl(value)).commit();
    }

    static String getDeviceId(Context context) {
        SharedPreferences preferences = prefs(context);
        String deviceId = preferences.getString(DEVICE_ID, null);
        if (deviceId != null && !deviceId.isEmpty()) {
            return deviceId;
        }
        deviceId = "phone-" + UUID.randomUUID().toString();
        preferences.edit().putString(DEVICE_ID, deviceId).commit();
        return deviceId;
    }

    static boolean isRelayEnabled(Context context) {
        return prefs(context).getBoolean(RELAY_ENABLED, false);
    }

    static void setRelayEnabled(Context context, boolean enabled) {
        prefs(context).edit().putBoolean(RELAY_ENABLED, enabled).commit();
    }

    static String publicMcpUrl(Context context) {
        String base = getRelayBaseUrl(context);
        if (base.isEmpty()) {
            return "Set relay base URL first.";
        }
        return base + "/d/" + getDeviceId(context) + "/mcp";
    }

    static String webSocketUrl(Context context) {
        String base = getRelayBaseUrl(context);
        if (base.isEmpty()) {
            return "";
        }
        String wsBase;
        if (base.toLowerCase(Locale.ROOT).startsWith("https://")) {
            wsBase = "wss://" + base.substring("https://".length());
        } else if (base.toLowerCase(Locale.ROOT).startsWith("http://")) {
            wsBase = "ws://" + base.substring("http://".length());
        } else {
            wsBase = "wss://" + base;
        }
        return wsBase + "/__phone_ws/" + getDeviceId(context);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static String normalizeBaseUrl(String value) {
        if (value == null) {
            return "";
        }
        String trimmed = value.trim();
        while (trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        if (trimmed.isEmpty()) {
            return "";
        }
        if (!trimmed.toLowerCase(Locale.ROOT).startsWith("http://")
            && !trimmed.toLowerCase(Locale.ROOT).startsWith("https://")) {
            return "https://" + trimmed;
        }
        return trimmed;
    }
}
