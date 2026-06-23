package com.lzh.devspaceandroid;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import java.security.SecureRandom;
import java.util.HashSet;
import java.util.Set;

final class TokenStore {
    private static final String PREFS = "devspace_android";
    private static final String OWNER_TOKEN = "owner_token";
    private static final String ACCESS_TOKENS = "access_tokens";
    private static final String REFRESH_TOKENS = "refresh_tokens";
    private final SharedPreferences preferences;

    TokenStore(Context context) {
        preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    String getOwnerToken() {
        String token = preferences.getString(OWNER_TOKEN, null);
        if (token != null && !token.isEmpty()) {
            return token;
        }
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        token = Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
        preferences.edit().putString(OWNER_TOKEN, token).apply();
        return token;
    }

    boolean isOwnerToken(String token) {
        return getOwnerToken().equals(token);
    }

    void addAccessToken(String token) {
        if (token == null || token.isEmpty()) {
            return;
        }
        Set<String> tokens = new HashSet<>(preferences.getStringSet(ACCESS_TOKENS, new HashSet<>()));
        tokens.add(token);
        preferences.edit().putStringSet(ACCESS_TOKENS, tokens).apply();
    }

    void addRefreshToken(String token) {
        if (token == null || token.isEmpty()) {
            return;
        }
        Set<String> tokens = new HashSet<>(preferences.getStringSet(REFRESH_TOKENS, new HashSet<>()));
        tokens.add(token);
        preferences.edit().putStringSet(REFRESH_TOKENS, tokens).apply();
    }

    boolean isAccessToken(String token) {
        if (token == null || token.isEmpty()) {
            return false;
        }
        return preferences.getStringSet(ACCESS_TOKENS, new HashSet<>()).contains(token);
    }

    boolean isRefreshToken(String token) {
        if (token == null || token.isEmpty()) {
            return false;
        }
        return preferences.getStringSet(REFRESH_TOKENS, new HashSet<>()).contains(token);
    }
}
