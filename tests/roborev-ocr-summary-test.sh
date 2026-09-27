#!/usr/bin/env bash
# Black-box tests for roborev-ocr-summary.sh. Mocks only the external
# boundary, the roborev CLI; jq, sed and git run for real.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../dot_claude/scripts/executable_roborev-ocr-summary.sh"

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
assert_eq()  { [[ "$1" == "$2" ]] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# Fresh sandbox with a fake roborev on PATH. `roborev log --raw` prints
# $WS/log (or fails when $WS/log-fails exists); `roborev show --json` prints a
# job whose range matches the fixtures' ocr_review input.
new_sandbox() {
  WS="$(mktemp -d)"
  mkdir -p "$WS/bin"
  cat >"$WS/bin/roborev" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  log)
    [[ -e "$WS/log-fails" ]] && { echo "roborev: job not found" >&2; exit 1; }
    cat "$WS/log";;
  show) echo '{"job":{"git_ref":"aaa..bbb","repo_path":"'"$WS"'"}}';;
esac
FAKE
  chmod +x "$WS/bin/roborev"
  export WS
}

# One ocr_review tool_use event carrying $1 (an OCR result object) as output.
ocr_event() {
  jq -cn --arg out "$1" '{type:"tool_use",part:{tool:"ocr_review",
    state:{status:"completed",input:{from:"aaa",to:"bbb"},output:$out}}}'
}

run() { # [HOME override]
  OUT="$(HOME="${1:-$HOME}" PATH="$WS/bin:$PATH" bash "$SCRIPT" 42 2>"$WS/stderr")"
  RC=$?
}

echo "renders a normal OCR result"
new_sandbox
ocr_event '{"status":"complete","message":"Review complete: 1 finding(s)","llm":{"provider":"p","model":"m"},"summary":{"elapsed":"1m"},"tool_calls":{"total":3,"failure":0},"groups":[{"label":"g","files":["a.sh"]}],"manifest":{"coverage":{"selected":[{"path":"a.sh"}],"completed":[{"path":"a.sh"}]}},"comments":[{"path":"a.sh","start_line":1,"end_line":1,"severity":"low","category":"bug","content":"broken"}]}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '**low** `a.sh:1` (bug): broken' "lists the finding"
assert_contains "$OUT" "1 selected, 1 completed" "reports coverage"

echo "a finding without content still renders"
new_sandbox
ocr_event '{"status":"complete","message":"m","llm":{"provider":"p","model":"m"},"summary":{"elapsed":"1m"},"tool_calls":{"total":1,"failure":1,"failure_details":[{"tool_name":"t","file_path":"a.sh"}]},"comments":[{"path":"a.sh","start_line":2,"end_line":2,"severity":"low","category":"bug"}]}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '`a.sh:2`' "lists the content-less finding"
assert_contains "$OUT" '`t` on `a.sh`' "lists the error-less tool failure"

echo "a partial payload renders no literal null"
new_sandbox
ocr_event '{"status":"complete","message":"m","comments":[]}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_not_contains "$OUT" "null" "no null in output"

echo "an unreadable log is an error, not a missing call"
new_sandbox
touch "$WS/log-fails"
run
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_not_contains "$OUT" "made no" "does not claim no call was made"

echo "a log with no JSON events is an error, not a missing call"
new_sandbox
echo "not json at all" >"$WS/log"
run
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_not_contains "$OUT" "made no" "does not claim no call was made"

echo "a log with events but no ocr_review call says so"
new_sandbox
jq -cn '{type:"text",part:{text:"hi"}}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" "made no \`ocr_review\` call" "reports the missing call"

echo "redacts a home directory containing regex metacharacters"
new_sandbox
fakehome="$WS/j[doe"
dashed="${fakehome#/}"
dashed="${dashed//\//-}"
jq -cn --arg err "write $fakehome/.ocr/s.jsonl: no space; session $dashed-proj" \
  '{type:"tool_use",part:{tool:"ocr_review",state:{status:"error",input:{from:"aaa",to:"bbb"},error:$err}}}' >"$WS/log"
run "$fakehome"
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" "write ~/.ocr/s.jsonl" "redacts the home path"
assert_contains "$OUT" "session ~-proj" "redacts the dash-encoded home path"
assert_not_contains "$OUT" "j[doe" "leaves no trace of the home directory"

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
