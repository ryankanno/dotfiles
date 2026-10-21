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

SANDBOXES="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$SANDBOXES"' EXIT

# Sets globals WS, LOG, OUT; fake ocr fails the scan when OCR_SCAN_FAIL=1
# and the export when OCR_EXPORT_FAIL=1.
new_sandbox() {
  WS="$(mktemp -d "$SANDBOXES/ws.XXXXXX")" || exit 1
  export LOG="$WS/calls.log"
  OUT="$WS/repo/.ocr-opencode"
  mkdir -p "$WS/bin"
  cat >"$WS/bin/ocr" <<'OCR'
#!/usr/bin/env bash
echo "ocr $*" >>"$LOG"
[[ "$1" == "scan" && "${OCR_SCAN_FAIL:-0}" == "1" ]] && exit 1
[[ "$1" == "session" && "${OCR_EXPORT_FAIL:-0}" == "1" ]] && exit 1
[[ "$1" == "session" ]] && echo "new" >"$4"
exit 0
OCR
  cat >"$WS/bin/opencode" <<'OC'
#!/usr/bin/env bash
echo "opencode $*" >>"$LOG"
OC
  chmod +x "$WS/bin/ocr" "$WS/bin/opencode"
  export PATH="$WS/bin:$PATH"
  git init -q "$WS/repo"
  : >"$LOG"
  cd "$WS/repo" || exit 1
}

echo "explore: scan, export, then opencode with the issue prompt"
new_sandbox
bash "$SCRIPT" explore src >/dev/null 2>&1
rc=$?
calls="$(cat "$LOG")"
assert_eq "$rc" "0" "exits 0"
assert_eq "$(sed -n 1p "$LOG")" "ocr scan --path src" "scans the given path first"
assert_contains "$(sed -n 2p "$LOG")" "ocr session export -o " "exports second"
assert_eq "$(cat "$OUT/review.html")" "new" "exports review.html into .ocr-opencode"
assert_eq "$(git status --porcelain)" "" "git does not see the outputs"
assert_contains "$(sed -n 3p "$LOG")" "opencode --prompt Read " "opens opencode with the explore prompt"
assert_contains "$calls" "$OUT/review.html." "explore reads review.html from .ocr-opencode at the repo root"
assert_eq "$(cat "$OUT/.gitignore")" "*" "writes a .gitignore that ignores the whole folder"
assert_eq "$([[ -e "$WS/repo/.git/ocr-opencode" ]] && echo yes)" "" "writes nothing into .git"
assert_not_contains "$calls" "/issue-to-pr" "explore does not send the fix prompt"
assert_contains "$calls" "Verify each issue in the code." "explore verifies each issue"
assert_contains "$calls" "File a GitHub issue only for an issue that you verify." "explore files only verified issues"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "3" "explore prompt is sent as one line"
assert_contains "$calls" "Assign each issue that you file to me." "explore assigns filed issues to me"
assert_contains "$calls" "Before you file an issue, search the open and closed issues. Do not file an issue that already exists." "explore does not file duplicates"
assert_contains "$calls" "If the gh user does not own the repository, do not file issues. Write each issue draft to " "explore files only on repos I own"
assert_contains "$calls" "ocr-opencode/review-issues.md instead." "explore drafts go to .ocr-opencode"

echo "fix: opencode gets the fix prompt"
new_sandbox
bash "$SCRIPT" fix src >/dev/null 2>&1
rc=$?
calls="$(cat "$LOG")"
assert_eq "$rc" "0" "fix exits 0"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "3" "fix prompt is sent as one line"
assert_contains "$calls" "Fix one bug at a time." "fix works one bug at a time"
assert_contains "$calls" "ocr-opencode/review.html, the ocr scan output." "opens opencode with the fix prompt"
assert_contains "$calls" "ocr-opencode/review-output.html, then stop." "fix prompt is sent whole, summary in review-output.html"
assert_not_contains "$calls" "review_output" "has no underscore file name"
assert_contains "$calls" "Fix the bug with TDD through /issue-to-pr." "fixes through issue-to-pr"
assert_contains "$calls" "Do not run another review, because /issue-to-pr runs the review rounds." "does not review twice"
assert_not_contains "$calls" "adversarial" "has no extra adversarial review"
assert_not_contains "$calls" "worktree" "does not make a shared worktree"
assert_contains "$calls" "Record the progress of each bug in " "fix records progress"
assert_contains "$calls" "ocr-opencode/review-progress.md." "progress goes to .ocr-opencode"
assert_contains "$calls" "ocr-opencode/review-progress.md, because review.html is new." "a new scan starts new progress in .ocr-opencode"
assert_not_contains "$calls" "old review-progress.md" "the reset names the full progress path"
assert_not_contains "$calls" "skip each bug" "a new scan does not resume"

echo "an existing review.html without --reuse is scanned again"
new_sandbox
mkdir -p "$OUT"
echo "old" >"$OUT/review.html"
bash "$SCRIPT" fix src >/dev/null 2>&1
assert_eq "$?" "0" "exits 0"
assert_eq "$(sed -n 1p "$LOG")" "ocr scan --path src" "scans again"
assert_eq "$(cat "$OUT/review.html")" "new" "replaces review.html"

echo "fix --reuse keeps review.html and resumes, without a src path"
new_sandbox
mkdir -p "$OUT"
echo "old" >"$OUT/review.html"
bash "$SCRIPT" fix --reuse >/dev/null 2>&1
rc=$?
calls="$(cat "$LOG")"
assert_eq "$rc" "0" "exits 0"
assert_eq "$(wc -l <"$LOG" | tr -d ' ')" "1" "runs only opencode"
assert_eq "$(cat "$OUT/review.html")" "old" "keeps review.html"
assert_contains "$calls" "ocr-opencode/review-progress.md exists, read it first, and skip each bug that it marks as done." "fix resumes from progress in .ocr-opencode"
assert_not_contains "$calls" "If review-progress.md" "the resume names the full progress path"
assert_not_contains "$calls" "Replace any old review-progress.md" "does not reset progress"

echo "fix --reuse without review.html fails"
new_sandbox
out="$(bash "$SCRIPT" fix --reuse 2>&1)"
assert_eq "$?" "2" "exits 2"
assert_contains "$out" "no review.html" "says why"
assert_eq "$(cat "$LOG")" "" "runs nothing"

echo "explore rejects --reuse"
new_sandbox
mkdir -p "$OUT"
echo "old" >"$OUT/review.html"
out="$(bash "$SCRIPT" explore --reuse 2>&1)"
assert_eq "$?" "2" "exits 2"
assert_contains "$out" "usage:" "prints usage"
assert_eq "$(cat "$LOG")" "" "runs nothing"

echo "scan failure stops the run"
new_sandbox
OCR_SCAN_FAIL=1 bash "$SCRIPT" explore src >/dev/null 2>&1
rc=$?
assert_eq "$rc" "1" "exits non-zero"
assert_not_contains "$(cat "$LOG")" "session export" "does not export after a failed scan"
assert_not_contains "$(cat "$LOG")" "opencode" "does not open opencode after a failed scan"

echo "export failure stops the run"
new_sandbox
OCR_EXPORT_FAIL=1 bash "$SCRIPT" explore src >/dev/null 2>&1
rc=$?
assert_eq "$rc" "1" "exits non-zero"
assert_eq "$(grep -c '^opencode ' "$LOG")" "0" "does not open opencode after a failed export"

echo "a linked worktree writes to its own .ocr-opencode"
new_sandbox
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git worktree add -q "$WS/wt"
cd "$WS/wt" || exit 1
bash "$SCRIPT" explore src >/dev/null 2>&1
assert_eq "$(cat "$WS/wt/.ocr-opencode/review.html")" "new" "exports review.html into the worktree .ocr-opencode"
assert_contains "$(sed -n 3p "$LOG")" "$WS/wt/.ocr-opencode/review.html." "the prompt names the worktree review.html"
assert_eq "$(ls -A "$WS/repo")" ".git" "writes nothing into the main checkout"
assert_eq "$(git status --porcelain)" "" "git does not see the outputs in the worktree"

echo "a run from a subdirectory writes to the repo root"
new_sandbox
mkdir -p "$WS/repo/sub"
cd "$WS/repo/sub" || exit 1
bash "$SCRIPT" explore . >/dev/null 2>&1
assert_eq "$(cat "$OUT/review.html")" "new" "exports review.html into .ocr-opencode at the repo root"
assert_eq "$(ls -A "$WS/repo/sub")" "" "writes nothing into the subdirectory"
assert_eq "$(git status --porcelain)" "" "git does not see the outputs"

echo "a run from outside a repository fails"
new_sandbox
mkdir -p "$WS/outside"
cd "$WS/outside" || exit 1
out="$(bash "$SCRIPT" explore "$WS/repo" 2>&1)"
assert_eq "$(($? != 0))" "1" "exits non-zero"
assert_contains "$out" "not a git repository" "says why"
assert_eq "$(ls -A "$WS/outside")" "" "writes no .ocr-opencode outside the repository"
assert_eq "$(ls -A "$WS/repo")" ".git" "writes no .ocr-opencode into the src repository"
assert_eq "$(cat "$LOG")" "" "runs nothing"

echo "bad arguments print usage"
new_sandbox
out="$(bash "$SCRIPT" nope src 2>&1)"
rc=$?
assert_eq "$rc" "2" "unknown workflow exits 2"
assert_contains "$out" "usage:" "prints usage"
out="$(bash "$SCRIPT" nope --reuse 2>&1)"
assert_contains "$out" "usage:" "unknown workflow with --reuse prints usage, not the review.html error"
bash "$SCRIPT" explore >/dev/null 2>&1
assert_eq "$?" "2" "missing path exits 2"
bash "$SCRIPT" explore src --nope >/dev/null 2>&1
assert_eq "$?" "2" "unknown flag exits 2"
bash "$SCRIPT" fix src --reuse >/dev/null 2>&1
assert_eq "$?" "2" "a src path with --reuse exits 2"
assert_eq "$(cat "$LOG")" "" "runs nothing on bad arguments"

echo
echo "pass: $PASS  fail: $FAIL"
[[ $FAIL -eq 0 ]]
