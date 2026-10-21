# Usage (from repo root): source plan/alief/ref/sim.sh
# Picks the first available iPhone simulator name, e.g. "iPhone 17 Pro" (no trailing space).
SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9]+(e| Pro Max| Pro| Plus| mini| Air)?' | head -1)
export SIM
echo "SIM=$SIM"
