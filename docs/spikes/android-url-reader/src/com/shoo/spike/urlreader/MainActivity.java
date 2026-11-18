package com.shoo.spike.urlreader;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Only a shortcut to the accessibility settings; all the work is in UrlReaderService. */
public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        TextView help = new TextView(this);
        help.setText("Enable \"Shoo Spike\" in accessibility settings, then browse in Chrome.\n\n"
                + "Results: adb logcat -s ShooSpike");

        Button open = new Button(this);
        open.setText("Open accessibility settings");
        open.setOnClickListener(v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));

        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER);
        column.setPadding(48, 48, 48, 48);
        column.addView(help);
        column.addView(open);
        setContentView(column);
    }
}
