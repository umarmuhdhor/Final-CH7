#!/usr/bin/env bash
# Installs the spike on the connected device or emulator, opens the test URLs in Chrome,
# and prints what the service read. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

SERVICE=com.shoo.spike.urlreader/com.shoo.spike.urlreader.UrlReaderService
CHROME="${CHROME:-com.android.chrome}"
WAIT_SECONDS="${WAIT_SECONDS:-6}"

adb wait-for-device
adb install -r build/shoo-spike.apk >/dev/null
adb shell pm path "$CHROME" >/dev/null || { echo "$CHROME is not installed"; exit 1; }

# Adds to the list instead of replacing it, so services already on (TalkBack...) stay on.
enabled="$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
case "$enabled" in
    *"$SERVICE"*) ;;
    null|"") adb shell settings put secure enabled_accessibility_services "$SERVICE" ;;
    *) adb shell settings put secure enabled_accessibility_services "$enabled:$SERVICE" ;;
esac
adb shell settings put secure accessibility_enabled 1
sleep 2

adb logcat -c
while read -r url; do
    [ -z "$url" ] && continue
    echo "OPEN $url"
    adb shell am start -a android.intent.action.VIEW -p "$CHROME" -d "\"$url\"" >/dev/null
    sleep "$WAIT_SECONDS"
done < test-urls.txt

adb exec-out screencap -p > build/last-screen.png
adb logcat -d -s ShooSpike:I
