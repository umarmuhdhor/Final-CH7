#!/usr/bin/env bash
# Builds the spike APK from the SDK tools alone (no Gradle, no downloads).
set -euo pipefail
cd "$(dirname "$0")"

: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
TOOLS="$ANDROID_HOME/build-tools/36.0.0"
JAR="$ANDROID_HOME/platforms/android-34/android.jar"
OUT=build

rm -rf "${OUT:?}/gen" "${OUT:?}/classes" "${OUT:?}/dex" "${OUT:?}"/*.apk "${OUT:?}"/*.idsig "${OUT:?}/res.zip"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

"$TOOLS/aapt2" compile --dir res -o "$OUT/res.zip"
"$TOOLS/aapt2" link -I "$JAR" --manifest AndroidManifest.xml --java "$OUT/gen" \
    -o "$OUT/unaligned.apk" "$OUT/res.zip"

javac --release 11 -classpath "$JAR" -d "$OUT/classes" $(find src "$OUT/gen" -name '*.java')
"$TOOLS/d8" --lib "$JAR" --min-api 26 --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')
zip -q -j "$OUT/unaligned.apk" "$OUT/dex/classes.dex"
"$TOOLS/zipalign" -f 4 "$OUT/unaligned.apk" "$OUT/shoo-spike.apk"

# Throwaway key, regenerated if build/ is deleted. Never used for a real release.
if [ ! -f "$OUT/spike.keystore" ]; then
    keytool -genkeypair -keystore "$OUT/spike.keystore" -alias spike -keyalg RSA -keysize 2048 \
        -validity 3650 -storepass android -keypass android -dname "CN=Shoo Spike" 2>/dev/null
fi
"$TOOLS/apksigner" sign --ks "$OUT/spike.keystore" --ks-pass pass:android "$OUT/shoo-spike.apk"
"$TOOLS/apksigner" verify "$OUT/shoo-spike.apk"
echo "Built $PWD/$OUT/shoo-spike.apk"
