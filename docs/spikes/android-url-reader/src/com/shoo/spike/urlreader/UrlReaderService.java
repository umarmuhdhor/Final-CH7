package com.shoo.spike.urlreader;

import android.accessibilityservice.AccessibilityService;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.TextView;

import java.util.ArrayDeque;
import java.util.List;
import java.util.TreeSet;

/**
 * Answers three questions, each as one logcat line under the tag ShooSpike:
 *   BAR   what the address bar node holds, and how fast we saw it change
 *   PAGE  what the web content exposes: its own URL, links, amount of text
 *   MISS  the address bar was not found
 * Text from the page is counted, never logged.
 */
public final class UrlReaderService extends AccessibilityService {
    private static final String TAG = "ShooSpike";
    private static final String URL_BAR_ID = ":id/url_bar";
    private static final long PAGE_PROBE_DELAY_MS = 2000;
    private static final int MAX_NODES = 5000;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable pageProbe = this::probePage;
    private String lastBarText;
    private String lastMissPackage;
    private long lastBarChangeAt;
    private TextView banner;

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || root.getPackageName() == null) return;

        String pkg = root.getPackageName().toString();
        List<AccessibilityNodeInfo> bars = root.findAccessibilityNodeInfosByViewId(pkg + URL_BAR_ID);
        if (bars.isEmpty()) {
            if (!pkg.equals(lastMissPackage)) {
                lastMissPackage = pkg;
                Log.i(TAG, "MISS pkg=" + pkg);
            }
            return;
        }

        AccessibilityNodeInfo bar = bars.get(0);
        // While focused the bar holds what the user is typing, not the page they are on.
        if (bar.isFocused() || bar.getText() == null) return;

        String text = bar.getText().toString();
        if (text.equals(lastBarText)) return;

        long now = SystemClock.uptimeMillis();
        lastBarText = text;
        lastBarChangeAt = now;
        Log.i(TAG, "BAR text=" + text + " sinceEventMs=" + (now - event.getEventTime()));
        showBanner(text);

        handler.removeCallbacks(pageProbe);
        handler.postDelayed(pageProbe, PAGE_PROBE_DELAY_MS);
    }

    /** Walks the tree once the page had time to load. Page text is only counted. */
    private void probePage() {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;

        long startedAt = SystemClock.uptimeMillis();
        ArrayDeque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        TreeSet<String> extraKeys = new TreeSet<>();
        queue.add(root);

        String rootWebAreaUrl = null;
        int nodes = 0;
        int links = 0;
        int textChars = 0;

        while (!queue.isEmpty() && nodes < MAX_NODES) {
            AccessibilityNodeInfo node = queue.poll();
            if (node == null) continue;
            nodes++;

            if (node.getText() != null) textChars += node.getText().length();

            Bundle extras = node.getExtras();
            extraKeys.addAll(extras.keySet());
            if (extras.getCharSequence("AccessibilityNodeInfo.targetUrl") != null) links++;
            if ("rootWebArea".equals(String.valueOf(extras.getCharSequence("AccessibilityNodeInfo.chromeRole")))
                    && extras.getCharSequence("url") != null) {
                rootWebAreaUrl = extras.getCharSequence("url").toString();
            }

            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) queue.add(child);
            }
        }

        Log.i(TAG, "PAGE bar=" + lastBarText
                + " rootWebAreaUrl=" + rootWebAreaUrl
                + " nodes=" + nodes
                + " links=" + links
                + " textChars=" + textChars
                + " walkMs=" + (SystemClock.uptimeMillis() - startedAt)
                + " sinceBarMs=" + (startedAt - lastBarChangeAt)
                + " extraKeys=" + extraKeys);
    }

    /** Proves an overlay can sit on top of Chrome with no extra permission. */
    private void showBanner(String text) {
        WindowManager windows = getSystemService(WindowManager.class);
        if (banner == null) {
            banner = new TextView(this);
            banner.setBackgroundColor(Color.parseColor("#CCB3261E"));
            banner.setTextColor(Color.WHITE);
            banner.setPadding(32, 16, 32, 16);

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.BOTTOM;
            windows.addView(banner, params);
        }
        banner.setText("Shoo saw: " + text);
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacks(pageProbe);
        if (banner != null) getSystemService(WindowManager.class).removeView(banner);
        super.onDestroy();
    }
}
