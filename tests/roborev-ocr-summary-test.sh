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

# Fresh sandbox with a fake roborev on PATH, replacing the previous one. It
# answers only the exact calls the script should make for job 42:
# `log --raw 42` prints $WS/log (or fails when $WS/log-fails exists), and
# `show --job 42 --json` prints a job whose git_ref is $WS/git_ref (default
# aaa..bbb) in repo $WS/repo.
new_sandbox() {
  [[ -n "${WS:-}" ]] && rm -rf "$WS"
  WS="$(mktemp -d)"
  mkdir -p "$WS/bin" "$WS/repo"
  echo "aaa..bbb" >"$WS/git_ref"
  cat >"$WS/bin/roborev" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "log --raw 42")
    [[ -e "$WS/log-fails" ]] && { echo "roborev: job not found" >&2; exit 1; }
    cat "$WS/log";;
  "show --job 42 --json")
    jq -cn --arg ref "$(cat "$WS/git_ref")" --arg repo "$WS/repo" '{job:{git_ref:$ref,repo_path:$repo}}';;
  *) echo "fake roborev: unexpected call: $*" >&2; exit 64;;
esac
FAKE
  chmod +x "$WS/bin/roborev"
  export WS
}
trap '[[ -n "${WS:-}" ]] && rm -rf "$WS"' EXIT

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
assert_contains "$OUT" "**Range check:** OCR reviewed the same change as the review" "range check matches"

echo "an ocr_review call on another range is flagged"
new_sandbox
jq -cn '{type:"tool_use",part:{tool:"ocr_review",state:{status:"completed",input:{from:"ccc",to:"bbb"},output:"{\"status\":\"complete\",\"message\":\"m\"}"}}}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" "**Range check: mismatch.** OCR reviewed range ccc..bbb, but the review covered range aaa..bbb." "range check reports the mismatch"

echo "a bare HTML tag in a finding cannot close the findings list early"
new_sandbox
ocr_event '{"status":"complete","message":"m","comments":[{"path":"a.sh","start_line":1,"end_line":1,"severity":"low","category":"bug","content":"stray </details> tag, quoted `</details>` tag"},{"path":"b.sh","start_line":1,"end_line":1,"severity":"low","category":"bug","content":"second"}]}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" 'stray &lt;/details> tag' "escapes the bare tag"
assert_contains "$OUT" 'quoted `</details>` tag' "leaves the tag in a code span as written"
assert_eq "$(sed 's/`[^`]*`//g' <<<"$OUT" | grep -c '</details>')" 2 "only the script's own two containers close"

echo "a bare HTML tag in a group label cannot close the files list early"
new_sandbox
ocr_event '{"status":"complete","message":"m","groups":[{"label":"x </details> y","files":["a.sh"]}]}' >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '- **x &lt;/details> y**: `a.sh`' "escapes the label"

echo "a JSON scalar line in the review body is not an event"
new_sandbox
{ ocr_event '{"status":"complete","message":"m"}'; echo "123"; echo "[1,2]"; } >"$WS/log"
run
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" "**Range check:** OCR reviewed the same change" "still renders the call"

echo "short SHAs from the agent match the full SHAs roborev stores"
new_sandbox
git -C "$WS/repo" init -q
git -C "$WS/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git -C "$WS/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
base=$(git -C "$WS/repo" rev-parse HEAD^)
head=$(git -C "$WS/repo" rev-parse HEAD)
echo "$base..$head" >"$WS/git_ref"
jq -cn --arg f "${base:0:7}" --arg t "${head:0:7}" '{type:"tool_use",part:{tool:"ocr_review",state:{status:"completed",input:{from:$f,to:$t},output:"{\"status\":\"complete\",\"message\":\"m\"}"}}}' >"$WS/log"
run
assert_contains "$OUT" "**Range check:** OCR reviewed the same change as the review, range ${base:0:7}..${head:0:7}." "resolves both sides before comparing"

echo "a single-commit call is compared as a commit"
new_sandbox
echo "ccc" >"$WS/git_ref"
jq -cn '{type:"tool_use",part:{tool:"ocr_review",state:{status:"completed",input:{commit:"ccc"},output:"{\"status\":\"complete\",\"message\":\"m\"}"}}}' >"$WS/log"
run
assert_contains "$OUT" "OCR reviewed the same change as the review, commit ccc." "matches a single commit"

echo "an uncommitted-changes job matches a call with no range"
new_sandbox
echo "dirty" >"$WS/git_ref"
jq -cn '{type:"tool_use",part:{tool:"ocr_review",state:{status:"completed",input:{},output:"{\"status\":\"complete\",\"message\":\"m\"}"}}}' >"$WS/log"
run
assert_contains "$OUT" "OCR reviewed the same change as the review, uncommitted changes." "matches uncommitted changes"

echo "several calls are numbered"
new_sandbox
{ ocr_event '{"status":"complete","message":"m"}'; ocr_event '{"status":"complete","message":"m"}'; } >"$WS/log"
run
assert_contains "$OUT" "### OCR cross-check (call 2 of 2)" "numbers the headings"
assert_contains "$OUT" "**Range check (call 2):**" "numbers the range checks"

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
