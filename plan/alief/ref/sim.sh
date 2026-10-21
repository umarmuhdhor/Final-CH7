# Usage (from repo root): source plan/alief/ref/sim.sh
# Picks the first available iPhone simulator name, e.g. "iPhone 17 Pro" (no trailing space).
SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9]+(e| Pro Max| Pro| Plus| mini| Air)?' | head -1)
export SIM
echo "SIM=$SIM"
# Bundle ID + App Group are per developer (L0: ios/Config/Local.xcconfig, defaults in ios/Config/Shoo.xcconfig).
# Read them from build settings instead of hardcoding com.shoo.app / group.com.shoo.app.
if [ -d ios/Shoo.xcodeproj ]; then
  BUILD_SETTINGS=$(xcodebuild -project ios/Shoo.xcodeproj -target Shoo -showBuildSettings 2>/dev/null)
  BUNDLE_ID=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')
  APP_GROUP=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ SHOO_APP_GROUP = /{print $2; exit}')
  export BUNDLE_ID APP_GROUP
  echo "BUNDLE_ID=$BUNDLE_ID APP_GROUP=$APP_GROUP"
fi
