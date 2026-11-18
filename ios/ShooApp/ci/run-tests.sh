#!/usr/bin/env bash
# C2 (#348): runs one half of the iOS suite from the `build-for-testing` products of the `build` job.
#   ios/ShooApp/ci/run-tests.sh unit|ui <path to .xctestrun> <simulator UDID>
# Writes xcodebuild-<kind>.log and results-<kind>.xcresult in the current folder; exits with xcodebuild's status.
#
# - unit: ShooAppTests, no retries (a unit test that fails once is a real failure).
# - ui:   ShooAppUITests without FigmaParityUITests (QA screenshots only, not a gate; 17 of 47 test minutes).
#         On a PR, only the classes select-ui-tests.sh picks from the changed files (a one-screen change
#         runs that screen's tests, not the 40-minute suite).
#         A failing UI test runs once more before it fails the job; the ones that only passed on the second
#         try are listed in the job summary, so a flaky test stays visible.
# - Both: a test that runs past 300 s is stopped, so one hung test can't eat the job timeout.
set -uo pipefail

kind=${1:?unit or ui}
xctestrun=${2:?path to the .xctestrun file}
udid=${3:?simulator UDID}
log="xcodebuild-$kind.log"

args=(
  test-without-building
  -xctestrun "$xctestrun"
  -destination "id=$udid"
  -resultBundlePath "results-$kind.xcresult"
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 300
)
case "$kind" in
  unit) args+=(-only-testing:ShooAppTests) ;;
  ui)
    # On a PR, only the classes the changed files can reach (select-ui-tests.sh). The checkout is the PR's
    # merge commit, so its diff against the first parent is exactly what the PR changes. If anything here
    # fails (not a PR, fetch error), the whole suite runs. SHOO_UI_CHANGED_FILES overrides the diff locally.
    here=$(cd "$(dirname "$0")" && pwd)
    changed=${SHOO_UI_CHANGED_FILES:-}
    if [ -z "$changed" ] && [ "${GITHUB_EVENT_NAME:-}" = pull_request ] \
      && git fetch --no-tags --quiet --depth=2 origin "${GITHUB_SHA:-HEAD}" 2>/dev/null; then
      changed=$(git diff --name-only "${GITHUB_SHA:-HEAD}^1" "${GITHUB_SHA:-HEAD}" 2>/dev/null || true)
    fi
    selection=ALL
    [ -n "$changed" ] && selection=$(printf '%s\n' "$changed" | "$here/select-ui-tests.sh")
    echo "UI test selection: $selection"
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "UI test selection: \`$selection\`" >> "$GITHUB_STEP_SUMMARY"
    case "$selection" in
      NONE)
        echo "No UI test can be affected by this PR's files; skipping the UI suite."
        exit 0
        ;;
      ALL) args+=(-only-testing:ShooAppUITests -skip-testing:ShooAppUITests/FigmaParityUITests) ;;
      *) for cls in $selection; do args+=("-only-testing:ShooAppUITests/$cls"); done ;;
    esac
    args+=(-retry-tests-on-failure -test-iterations 2)
    ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

# The full log is too long to read: print each finished test as it happens (a cancelled run still shows how
# far it got and what took the time), then the tail and every assertion line, so a failure shows why.
xcodebuild "${args[@]}" 2>&1 | tee "$log" | grep --line-buffered -iE "^Test case .* (passed|failed|skipped) (on|\()"
status=${PIPESTATUS[0]}

tail -40 "$log"
echo "::group::Assertion failures"
grep -E ": error: |\] failed \(|' failed on |recorded an issue|Expectation failed" "$log" | cut -c1-600 | head -60 || true
echo "::endgroup::"

# A test with a "failed" line and a later "passed" line passed only on its retry.
retried=$(grep -iE "^Test case '[^']+' (passed|failed) " "$log" \
  | sed -E "s/^Test [Cc]ase '([^']+)' (passed|failed) .*/\2\t\1/" \
  | awk -F '\t' '$1 == "failed" { failed[$2] = 1 } $1 == "passed" && failed[$2] { print $2 }' | sort -u)
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### iOS $kind tests"
    if [ -n "$retried" ]; then
      echo "Passed after retry (flaky, look at these):"
      echo "$retried" | sed 's/^/- `/; s/$/`/'
    else
      echo "No test needed a retry."
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$status"
