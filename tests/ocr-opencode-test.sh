#!/usr/bin/env bash
# Black-box tests for ocr-opencode.sh. Mocks only the external boundaries:
#   ocr -> LLM scan        opencode -> agent TUI
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/executable_ocr-opencode.sh"

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
assert_not_contains "$calls" "/issue-to-pr" "explore does not send the fix prompt"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "3" "explore prompt is sent as one line"
assert_contains "$calls" "Assign each issue that you file to me." "explore assigns filed issues to me"
assert_contains "$calls" "Before you file an issue, search the open and closed issues. Do not file an issue that already exists." "explore does not file duplicates"
assert_contains "$calls" "If the gh user does not own the repository, do not file issues. Write each issue draft to review-issues.md instead." "explore files only on repos I own"

echo "fix: opencode gets the fix prompt"
new_sandbox
bash "$SCRIPT" fix src >/dev/null 2>&1
calls="$(cat "$LOG")"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "3" "fix prompt is sent as one line"
assert_contains "$calls" "opencode --prompt Read review.html, the ocr scan output." "opens opencode with the fix prompt"
assert_contains "$calls" "Write the final summary to review_output.html, then stop." "fix prompt is sent whole"
assert_contains "$calls" "Fix the bug with TDD through /issue-to-pr." "fixes through issue-to-pr"
assert_contains "$calls" "Do not run another review, because /issue-to-pr runs the review rounds." "does not review twice"
assert_not_contains "$calls" "adversarial" "has no extra adversarial review"
assert_not_contains "$calls" "worktree" "does not make a shared worktree"
assert_contains "$calls" "Record the progress of each bug in review-progress.md." "fix records progress"
assert_contains "$calls" "Replace any old review-progress.md, because review.html is new." "a new scan starts new progress"
assert_not_contains "$calls" "skip each bug" "a new scan does not resume"

echo "an existing review.html without --reuse is scanned again"
new_sandbox
echo "old" >review.html
bash "$SCRIPT" fix src >/dev/null 2>&1
assert_eq "$(sed -n 1p "$LOG")" "ocr scan --path src" "scans again"

echo "--reuse keeps review.html and resumes"
new_sandbox
echo "old" >review.html
bash "$SCRIPT" fix src --reuse >/dev/null 2>&1
calls="$(cat "$LOG")"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "1" "runs only opencode"
assert_eq "$(cat review.html)" "old" "keeps review.html"
assert_contains "$calls" "If review-progress.md exists, read it first, and skip each bug that it marks as done." "fix resumes from progress"
assert_not_contains "$calls" "Replace any old review-progress.md" "does not reset progress"

echo "--reuse without review.html fails"
new_sandbox
out="$(bash "$SCRIPT" fix src --reuse 2>&1)"
assert_eq "$?" "2" "exits 2"
assert_contains "$out" "no review.html" "says why"
assert_eq "$(cat "$LOG")" "" "runs nothing"

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
bash "$SCRIPT" explore >/dev/null 2>&1
assert_eq "$?" "2" "missing path exits 2"
bash "$SCRIPT" explore src --nope >/dev/null 2>&1
assert_eq "$?" "2" "unknown flag exits 2"
assert_eq "$(cat "$LOG")" "" "runs nothing on bad arguments"

echo
echo "pass: $PASS  fail: $FAIL"
[[ $FAIL -eq 0 ]]
