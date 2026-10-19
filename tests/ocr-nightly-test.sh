#!/usr/bin/env bash
# Black-box tests for ocr-nightly.sh. Mocks only the external boundaries:
#   ocr -> LLM scan        opencode -> agent TUI
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/executable_ocr-nightly.sh"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1" >&2; }

assert_contains() { # haystack needle msg
  case "$1" in
    *"$2"*) ok "$3";;
    *) bad "$3 (expected to contain: $2)";;
  esac
}
assert_not_contains() {
  case "$1" in
    *"$2"*) bad "$3 (should NOT contain: $2)";;
    *) ok "$3";;
  esac
}
assert_eq() { [[ "$1" == "$2" ]] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# Sets globals WS, LOG; fake ocr fails the scan when OCR_SCAN_FAIL=1.
new_sandbox() {
  WS="$(mktemp -d)"
  export LOG="$WS/calls.log"
  : >"$LOG"
  mkdir -p "$WS/bin"
  cat >"$WS/bin/ocr" <<'OCR'
#!/usr/bin/env bash
echo "ocr $*" >>"$LOG"
[[ "$1" == "scan" && "${OCR_SCAN_FAIL:-0}" == "1" ]] && exit 1
exit 0
OCR
  cat >"$WS/bin/opencode" <<'OC'
#!/usr/bin/env bash
echo "opencode $*" >>"$LOG"
OC
  chmod +x "$WS/bin/ocr" "$WS/bin/opencode"
  export PATH="$WS/bin:$PATH"
  cd "$WS" || exit 1
}

echo "explore: scan, export, then opencode with the issue prompt"
new_sandbox
bash "$SCRIPT" explore src >/dev/null 2>&1
rc=$?
calls="$(cat "$LOG")"
assert_eq "$rc" "0" "exits 0"
assert_eq "$(sed -n 1p "$LOG")" "ocr scan --path src" "scans the given path first"
assert_eq "$(sed -n 2p "$LOG")" "ocr session export -o review.html" "exports review.html second"
assert_contains "$(sed -n 3p "$LOG")" "opencode --prompt Read review.html." "opens opencode with the explore prompt"
assert_not_contains "$calls" "fix/review-critical-highs" "explore does not send the fix prompt"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "3" "explore prompt is sent as one line"
assert_contains "$calls" "Assign each issue that you file to me." "explore assigns filed issues to me"

echo "fix: opencode gets the fix prompt"
new_sandbox
bash "$SCRIPT" fix src >/dev/null 2>&1
calls="$(cat "$LOG")"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "3" "fix prompt is sent as one line"
assert_contains "$calls" "opencode --prompt Make a new worktree named fix/review-critical-highs." "opens opencode with the fix prompt"
assert_contains "$calls" "Write the final summary to review_output.html, then stop." "fix prompt is sent whole"
assert_contains "$calls" "Open each PR as a draft, and keep it as a draft." "fix keeps PRs as drafts"
assert_contains "$calls" "Assign each PR to me." "fix assigns PRs to me"
assert_contains "$calls" "Record the progress of each bug in review-progress.md." "fix records progress"
assert_contains "$calls" "If review-progress.md exists, read it first, and skip each bug that it marks as done." "fix resumes from progress"

echo "an existing review.html is reused"
new_sandbox
echo "old" >review.html
out="$(bash "$SCRIPT" fix src 2>&1)"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "1" "runs only opencode"
assert_contains "$(cat "$LOG")" "opencode --prompt" "opens opencode"
assert_eq "$(cat review.html)" "old" "keeps review.html"
assert_contains "$out" "delete review.html" "says how to get a new scan"

echo "scan failure stops the run"
new_sandbox
OCR_SCAN_FAIL=1 bash "$SCRIPT" explore src >/dev/null 2>&1
rc=$?
assert_eq "$rc" "1" "exits non-zero"
assert_not_contains "$(cat "$LOG")" "session export" "does not export after a failed scan"
assert_not_contains "$(cat "$LOG")" "opencode" "does not open opencode after a failed scan"

echo "bad arguments print usage"
new_sandbox
out="$(bash "$SCRIPT" nope src 2>&1)"
rc=$?
assert_eq "$rc" "2" "unknown workflow exits 2"
assert_contains "$out" "usage:" "prints usage"
out="$(bash "$SCRIPT" explore 2>&1)"
assert_eq "$?" "2" "missing path exits 2"
assert_eq "$(cat "$LOG")" "" "runs nothing on bad arguments"

echo
echo "pass: $PASS  fail: $FAIL"
[[ $FAIL -eq 0 ]]
