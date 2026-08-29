package com.lzh.devspaceandroid;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.net.Inet4Address;
import java.net.NetworkInterface;
import java.util.Collections;

public final class MainActivity extends Activity {
    private final Handler handler = new Handler();
    private TextView status;
    private TextView endpoint;
    private TextView token;
    private EditText relayInput;
    private TextView publicUrl;
    private TextView relayStatus;
    private TextView relayLog;
    private TextView root;
    private TextView locations;
    private final Runnable refresh = new Runnable() {
        @Override
        public void run() {
            updateStatus();
            handler.postDelayed(this, 1000L);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestNotificationPermission();
        setContentView(buildUi());
        updateStatus();
    }

    @Override
    protected void onResume() {
        super.onResume();
        handler.post(refresh);
    }

    @Override
    protected void onPause() {
        handler.removeCallbacks(refresh);
        super.onPause();
    }

    private View buildUi() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(20), dp(22), dp(20), dp(22));
        scroll.addView(layout);

        TextView title = text("DevSpace Android", 26, true);
        layout.addView(title);
        layout.addView(text("Phone-local MCP server for GPT file control.", 14, false));
        layout.addView(spacer(16));

        status = text("", 16, true);
        endpoint = selectableText("");
        token = selectableText("");
        publicUrl = selectableText("");
        relayStatus = text("", 14, true);
        relayLog = selectableText("");
        root = selectableText("");
        locations = selectableText("");
        layout.addView(status);
        layout.addView(spacer(10));
        layout.addView(label("MCP URL"));
        layout.addView(endpoint);
        layout.addView(label("Owner token"));
        layout.addView(token);
        layout.addView(label("Phone-direct public MCP URL"));
        layout.addView(publicUrl);
        layout.addView(label("Relay base URL"));
        relayInput = new EditText(this);
        relayInput.setSingleLine(true);
        relayInput.setHint("https://your-worker.your-name.workers.dev");
        relayInput.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        relayInput.setText(RelayConfig.getRelayBaseUrl(this));
        layout.addView(relayInput);
        layout.addView(label("Relay status"));
        layout.addView(relayStatus);
        layout.addView(label("Relay log"));
        layout.addView(relayLog);
        layout.addView(label("Allowed root"));
        layout.addView(root);
        layout.addView(label("Known file locations"));
        layout.addView(locations);
        layout.addView(spacer(16));

        Button start = button("Start MCP server");
        start.setOnClickListener(view -> PhoneMcpService.start(this));
        layout.addView(start);

        Button stop = button("Stop MCP server");
        stop.setOnClickListener(view -> PhoneMcpService.stop(this));
        layout.addView(stop);

        Button copyUrl = button("Copy MCP URL");
        copyUrl.setOnClickListener(view -> copy("MCP URL", endpoint.getText().toString()));
        layout.addView(copyUrl);

        Button copyToken = button("Copy owner token");
        copyToken.setOnClickListener(view -> copy("Owner token", tokenValue()));
        layout.addView(copyToken);

        Button saveRelay = button("Save relay URL");
        saveRelay.setOnClickListener(view -> saveRelayUrl());
        layout.addView(saveRelay);

        Button startRelay = button("Start phone-direct tunnel");
        startRelay.setOnClickListener(view -> {
            saveRelayUrl();
            PhoneMcpService.startRelay(this);
        });
        layout.addView(startRelay);

        Button stopRelay = button("Stop phone-direct tunnel");
        stopRelay.setOnClickListener(view -> PhoneMcpService.stopRelay(this));
        layout.addView(stopRelay);

        Button copyPublicUrl = button("Copy public MCP URL");
        copyPublicUrl.setOnClickListener(view -> copy("Public MCP URL", publicUrl.getText().toString()));
        layout.addView(copyPublicUrl);

        Button grant = button("Grant all-files access");
        grant.setOnClickListener(view -> openAllFilesSettings());
        layout.addView(grant);

        Button battery = button("Allow background running");
        battery.setOnClickListener(view -> openBatteryOptimizationSettings());
        layout.addView(battery);

        layout.addView(spacer(18));
        layout.addView(text("Phone-direct mode uses a deployed HTTPS relay. The phone keeps an outbound WebSocket open, and ChatGPT connects to the public MCP URL. The owner token is required on the approval page and is also accepted as a Bearer token for local testing. If a relay URL is saved, the app tries to restart phone-direct mode after phone reboot or app update.", 14, false));
        return scroll;
    }

    private void updateStatus() {
        boolean running = PhoneMcpService.isRunning();
        FileTools fileTools = new FileTools(this);
        RelayClient relayClient = RelayClient.get(this);
        status.setText(running ? "Status: running on port " + McpServer.PORT : "Status: stopped");
        endpoint.setText("http://" + localIp() + ":" + McpServer.PORT + "/mcp");
        publicUrl.setText(RelayConfig.publicMcpUrl(this));
        relayStatus.setText(relayClient.statusLine());
        relayLog.setText(relayClient.lastMessage());
        String relayBase = RelayConfig.getRelayBaseUrl(this);
        if (relayInput != null && !relayInput.hasFocus() && !relayInput.getText().toString().equals(relayBase)) {
            relayInput.setText(relayBase);
        }
        token.setText(tokenValue());
        root.setText(fileTools.rootLabel() + (hasAllFilesAccess() ? " (all-files access)" : " (app-private until permission is granted)"));
        locations.setText(fileTools.knownRoots());
    }

    private void saveRelayUrl() {
        RelayConfig.setRelayBaseUrl(this, relayInput.getText().toString());
        updateStatus();
        Toast.makeText(this, "Relay URL saved", Toast.LENGTH_SHORT).show();
    }

    private String tokenValue() {
        return new TokenStore(this).getOwnerToken();
    }

    private boolean hasAllFilesAccess() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager();
    }

    private void openAllFilesSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            Toast.makeText(this, "All-files access setting is not required on this Android version.", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
        intent.setData(Uri.parse("package:" + getPackageName()));
        startActivity(intent);
    }

    private void openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Toast.makeText(this, "Battery optimization setting is not required on this Android version.", Toast.LENGTH_SHORT).show();
            return;
        }
        PowerManager powerManager = (PowerManager) getSystemService(POWER_SERVICE);
        if (powerManager != null && powerManager.isIgnoringBatteryOptimizations(getPackageName())) {
            Toast.makeText(this, "Battery optimization is already ignored for this app.", Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        } catch (Exception ignored) {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 33);
        }
    }

    private String localIp() {
        try {
            for (NetworkInterface networkInterface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                for (java.net.InetAddress address : Collections.list(networkInterface.getInetAddresses())) {
                    if (!address.isLoopbackAddress() && address instanceof Inet4Address) {
                        return address.getHostAddress();
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return "127.0.0.1";
    }

    private void copy(String label, String value) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value));
        Toast.makeText(this, label + " copied", Toast.LENGTH_SHORT).show();
    }

    private TextView text(String value, int sp, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(0xff172426);
        view.setGravity(Gravity.START);
        if (bold) {
            view.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        }
        view.setPadding(0, dp(3), 0, dp(3));
        return view;
    }

    private TextView selectableText(String value) {
        TextView view = text(value, 14, false);
        view.setTextIsSelectable(true);
        view.setInputType(InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        view.setBackgroundColor(0xffeef5f4);
        view.setPadding(dp(10), dp(10), dp(10), dp(10));
        return view;
    }

    private TextView label(String value) {
        TextView view = text(value, 12, true);
        view.setTextColor(0xff557174);
        view.setPadding(0, dp(12), 0, dp(4));
        return view;
    }

    private Button button(String value) {
        Button button = new Button(this);
        button.setText(value);
        button.setAllCaps(false);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48));
        params.setMargins(0, dp(6), 0, 0);
        button.setLayoutParams(params);
        return button;
    }

    private View spacer(int heightDp) {
        View view = new View(this);
        view.setLayoutParams(new LinearLayout.LayoutParams(1, dp(heightDp)));
        return view;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
