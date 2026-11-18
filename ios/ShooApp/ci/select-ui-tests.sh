#!/usr/bin/env bash
# Picks the UI test classes a PR has to run, from the files it changes, so a change to one screen does not
# wait 40 minutes for the whole suite.
#   git diff --name-only <base> <head> | ios/ShooApp/ci/select-ui-tests.sh
# Prints one of:
#   ALL                    run the whole gated suite (anything shared, or a path this map does not know)
#   NONE                   no UI test can be affected (unit tests, docs)
#   <Class> <Class> ...    only these ShooAppUITests classes
#
# The map below comes from which accessibility identifiers of each Features/<Area> folder every UI test (and
# the UITestSupport helpers it calls) looks up. When a test starts using a screen from another area, add the
# test to that area here. When in doubt, a path falls through to ALL.
set -euo pipefail

# Gated classes (run-tests.sh skips FigmaParityUITests; the Live*, PairingGate and Accessibility tests skip
# themselves without their env). SmokeUITests is cheap (~45 s) and runs on every selection.
ALWAYS="SmokeUITests"

area_tests() {
  case "$1" in
    Activity) echo "ProtectedUITests GuardianUITests DeepLinkUITests QALayoutUITests" ;;
    Detail) echo "DetailUITests DeepLinkUITests GuardianUITests LaunchSplashUITests ProtectedUITests QALayoutUITests" ;;
    # UITestSupport's onboarding helpers (onboardName, becomeGuardian) are used by Guardian, Onboarding, Pairing.
    Onboarding) echo "OnboardingUITests LaunchSplashUITests PairingUITests ProfileUITests QALayoutUITests SessionUITests GuardianUITests" ;;
    Pairing) echo "PairingUITests ProfileUITests GuardianUITests QALayoutUITests" ;;
    Profile) echo "ProfileUITests PairingUITests DeepLinkUITests LaunchSplashUITests" ;;
    Shield) echo "GuardianUITests ProtectedUITests PairingUITests OnboardingUITests QALayoutUITests DeepLinkUITests LaunchSplashUITests ProfileUITests" ;;
    *) echo ALL ;; # Main (tab bar, every test passes through it) and any new area
  esac
}

selected=""
all=false
while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    ios/ShooApp/Tests/*) ;; # unit tests only
    *.md) ;;
    ios/ShooApp/UITests/UITestSupport.swift) all=true ;;
    ios/ShooApp/UITests/*.swift)
      cls=$(basename "$path" .swift)
      [ "$cls" = FigmaParityUITests ] || selected+=" $cls"
      ;;
    ios/ShooApp/Features/*/*)
      area=${path#ios/ShooApp/Features/}
      tests=$(area_tests "${area%%/*}")
      if [ "$tests" = ALL ]; then all=true; else selected+=" $tests"; fi
      ;;
    # App, Components, Data, Resources (strings, colors), Support, Debug, ci/, the plist and entitlements,
    # ShooShared, project.yml, contracts/fixtures, the workflow: every screen can feel these.
    *) all=true ;;
  esac
  if $all; then break; fi
done

if $all; then
  echo ALL
elif [ -z "$selected" ]; then
  echo NONE
else
  echo "$ALWAYS $selected" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//'
  echo
fi
