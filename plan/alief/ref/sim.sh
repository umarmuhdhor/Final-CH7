# Usage (from repo root): source plan/alief/ref/sim.sh
# Picks an iPhone simulator on the newest installed iOS runtime that is not newer than the Xcode SDK.
# Use SIM_ID: `-destination "platform=iOS Simulator,id=$SIM_ID"`. A name alone resolves to OS:latest
# (= the SDK version) and fails when that runtime is not installed, or picks the wrong one of two
# devices with the same name (29 Okt: SDK 27.1, runtime 27.0 only). SIM stays for old commands.
SIM_LINE=$(xcrun simctl list devices available -j | python3 -I -c '
import json, subprocess, sys
sdk = tuple(int(x) for x in subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]).decode().split("."))
best = None
for key, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in key:
        continue
    version = tuple(int(x) for x in key.split(".iOS-")[1].split("-"))
    phones = [d for d in devices if d["name"].startswith("iPhone")]
    if phones and version <= sdk and (best is None or version > best[0]):
        best = (version, phones[0])
print(best[1]["udid"] + "\t" + best[1]["name"] if best else "")')
SIM_ID=${SIM_LINE%%$'\t'*}
SIM=${SIM_LINE#*$'\t'}
export SIM SIM_ID
echo "SIM=$SIM SIM_ID=$SIM_ID"
# Bundle ID + App Group are per developer (L0: ios/Config/Local.xcconfig, defaults in ios/Config/Shoo.xcconfig).
# Read them from build settings instead of hardcoding com.shoo.app / group.com.shoo.app.
if [ -d ios/Shoo.xcodeproj ]; then
  BUILD_SETTINGS=$(xcodebuild -project ios/Shoo.xcodeproj -target Shoo -showBuildSettings 2>/dev/null)
  BUNDLE_ID=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')
  APP_GROUP=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ SHOO_APP_GROUP = /{print $2; exit}')
  export BUNDLE_ID APP_GROUP
  echo "BUNDLE_ID=$BUNDLE_ID APP_GROUP=$APP_GROUP"
else
  echo "BUNDLE_ID/APP_GROUP kosong: jalankan (cd ios && xcodegen) dulu, lalu source ulang" >&2
fi
