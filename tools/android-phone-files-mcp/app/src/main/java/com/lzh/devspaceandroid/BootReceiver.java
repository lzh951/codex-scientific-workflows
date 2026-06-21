package com.lzh.devspaceandroid;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String relayBaseUrl = RelayConfig.getRelayBaseUrl(context);
        if (relayBaseUrl == null || relayBaseUrl.isEmpty()) {
            return;
        }
        Intent service = new Intent(context, PhoneMcpService.class).setAction(PhoneMcpService.ACTION_START_RELAY);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service);
            } else {
                context.startService(service);
            }
        } catch (RuntimeException ignored) {
        }
    }
}
