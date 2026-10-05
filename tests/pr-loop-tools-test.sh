#!/usr/bin/env bash
# Tests for the pr-loop tool bindings: the ocr reviewer wrapper's argument
# contract and the renderer's markdown. Fixtures mirror the ocr v1.12.11 json
# shape, pinned from a live run 2026-10-03; the wrapper tests stub the ocr
# binary because the real one is a billed LLM service.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/dot_claude/skills/issue-to-pr/tools"
REVIEW="$TOOLS/ocr/executable_review.sh"
RENDER="$TOOLS/ocr/executable_render.sh"
PASS=0 FAIL=0
WS=""
SANDBOXES=()

# The suite runs under set -u only: a failing command is tallied by the
# assert_* helpers, never fatal. No helper may switch errexit on; one
# leaked `set -e` silently turns every later failure into a truncated
# run with no summary.
new_sandbox() { WS="$(mktemp -d "${TMPDIR:-/tmp}/pr-loop-test.XXXXXXXX")"; SANDBOXES+=("$WS"); }
trap '[[ ${#SANDBOXES[@]} -eq 0 ]] || rm -rf "${SANDBOXES[@]}"' EXIT
render() { OUT="$("$RENDER" "$WS" 2>&1)"; RC=$?; }
report() {
  echo
  echo "passed: $PASS  failed: $FAIL"
  [[ $FAIL -eq 0 ]]
}
assert_eq() {
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$3" "$2" "$1"
  fi
}
assert_contains() {
  if grep -qF -- "$2" <<<"$1"; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  missing: %s\n' "$3" "$2"
  fi
}
assert_not_contains() {
  if grep -qF -- "$2" <<<"$1"; then
    FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  unexpectedly present: %s\n' "$3" "$2"
  else PASS=$((PASS + 1)); fi
}
assert_json() {
  if jq -e "$1" "$2" >/dev/null 2>&1; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  expression: %s\n  file: %s\n' "$3" "$1" "$2"
  fi
}

fixture_full() {
  jq -cn '{
    status: "complete",
    llm: {provider: "test-provider", model: "test-model"},
    message: "Review complete: 2 finding(s) across 1 selected item(s).",
    summary: {files_reviewed: 1, comments: 2, total_tokens: 17248,
      input_tokens: 16456, output_tokens: 792, cache_read_tokens: 8832,
      elapsed: "4s"},
    tool_calls: {total: 1, by_tool: {code_comment: 1}, failure: 0,
      failure_by_tool: {}, failure_details: []},
    comments: [
      {path: "calc.py",
       content: "Mutable default argument: `bucket=[]` is shared across every call.",
       suggestion_code: "def collect(item, bucket=None):",
       start_line: 7, end_line: 7, category: "bug", severity: "high"},
      {path: "calc.py",
       content: "Bare `except:` swallows everything.",
       suggestion_code: "    except Exception as e:\n        pass",
       start_line: 10, end_line: 11, category: "bug", severity: "high"}
    ],
    groups: [{label: "calc.py", files: ["calc.py"]}],
    session_id: "288a5029-d175-454f-8575-4c6af2964fa5",
    manifest: {input: {mode: "range",
        requested_from: "aaa", requested_head: "bbb",
        resolved_base: "aaaa", resolved_head: "bbbb",
        exact_range: "aaaa..bbbb"},
      execution: {ocr_version: "v1.12.11"},
      coverage: {selected: [{path: "calc.py"}], completed: [{path: "calc.py"}],
        failed: [], waived: [], reused: []}}
  }' >"$WS/review.json"
}

fixture_minimal() { jq -cn "$1" >"$WS/review.json"; }

echo "renderer: every section from a findings-bearing run"
new_sandbox
fixture_full
render
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '- **Reviewer:** OpenCodeReview `v1.12.11`.' "identity"
assert_not_contains "$OUT" 'test-provider' "the llm provider never reaches the comment"
assert_not_contains "$OUT" 'test-model' "the llm model never reaches the comment"
assert_contains "$OUT" '- **Status:** `complete`. Review complete: 2 finding(s) across 1 selected item(s).' "status with message"
assert_contains "$OUT" '- **Range:** `aaaa..bbbb` (mode `range`), resolved by the orchestrator from the PR.' "range and mode"
assert_contains "$OUT" '- **Tokens:** 17248 total (16456 input, 792 output, 8832 cache read), elapsed 4s.' "tokens"
assert_contains "$OUT" '- **Tool calls:** 1 (0 failed): `code_comment` 1' "tool calls by tool"
assert_contains "$OUT" '- **Files:** 1 selected, 1 completed, 0 failed, 0 waived, 0 reused.' "file coverage"
assert_contains "$OUT" '1. **bug/high** `calc.py`:7-7: Mutable default argument' "first finding numbered"
assert_contains "$OUT" '2. **bug/high** `calc.py`:10-11: Bare `except:` swallows everything.' "second finding numbered"
assert_contains "$OUT" '~~~' "suggestion is fenced"
assert_contains "$OUT" '- **Session:** `288a5029-d175-454f-8575-4c6af2964fa5`' "session id"

echo "renderer: a clean run says none, not null"
new_sandbox
fixture_minimal '{"status":"complete","message":"Review complete: 0 finding(s).","comments":[],
  "manifest":{"input":{"mode":"commit","exact_range":"x..y"},"execution":{},"coverage":{}}}'
render
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '- **Findings:** none.' "clean says none"
assert_not_contains "$OUT" 'null' "no null in output"

echo "renderer: missing summary and tool_calls say unknown"
new_sandbox
fixture_minimal '{"status":"complete","comments":[],"manifest":{"input":{}}}'
render
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '- **Tokens:** unknown' "tokens unknown"
assert_contains "$OUT" '- **Tool calls:** unknown (unknown failed)' "tool calls unknown"
assert_contains "$OUT" '- **Reviewer:** OpenCodeReview `unknown`.' "version unknown"
assert_not_contains "$OUT" 'null' "no null in output"

echo "renderer: a finding cannot close the collapsed block"
new_sandbox
fixture_minimal '{"status":"complete","comments":[
  {"path":"a.md","content":"closes early </details> and keeps going","start_line":1,"category":"bug","severity":"high"}]}'
render
assert_eq "$RC" 0 "exits 0"
assert_not_contains "$OUT" '</details>' "no raw close tag"
assert_contains "$OUT" '&lt;/details&gt;' "escaped close tag"

echo "renderer: details tags are entity-escaped in every form"
new_sandbox
fixture_minimal '{"status":"complete","comments":[
  {"path":"a.md","content":"opens <details> then </DETAILS> and </details > too","start_line":1,"category":"bug","severity":"high"}]}'
render
assert_eq "$RC" 0 "exits 0"
assert_not_contains "$OUT" '<details>' "no raw opening tag"
assert_not_contains "$OUT" '</DETAILS>' "no raw uppercase close tag"
assert_not_contains "$OUT" '</details >' "no raw spaced close tag"
assert_contains "$OUT" '&lt;details&gt;' "opening tag entity-escaped"
assert_contains "$OUT" '&lt;/details&gt;' "close tag entity-escaped"

echo "renderer: null content reads unknown, not the literal null"
new_sandbox
fixture_minimal '{"status":"complete","comments":[{"path":"a.md","content":null,"start_line":1}]}'
render
assert_not_contains "$OUT" ': null' "no literal null in the findings line"
assert_contains "$OUT" 'unknown' "null content reads as unknown"

echo "renderer: the fence beats a five-tilde run, not just the minimum"
new_sandbox
fixture_minimal '{"status":"complete","comments":[
  {"path":"a.py","content":"c","suggestion_code":"x = ~~~~~\ny","start_line":1}]}'
render
assert_eq "$(printf '%s\n' "$OUT" | grep -cE '^[[:space:]]*~~~~~~$')" 2 "fence is six tildes, top and bottom"

echo "renderer: tilde runs inside a suggestion cannot close the fence"
new_sandbox
fixture_minimal '{"status":"complete","comments":[
  {"path":"a.py","content":"c","suggestion_code":"x = ~~~\ny","start_line":1,"category":"bug","severity":"low"}]}'
render
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '~~~~' "fence beats the longest run"

echo "renderer: a multi-line suggestion keeps the whole block in the list item"
new_sandbox
fixture_minimal '{"status":"complete","comments":[
  {"path":"a.py","content":"c","suggestion_code":"line one\nline two","start_line":1,"category":"bug","severity":"low"}]}'
render
assert_eq "$RC" 0 "exits 0"
assert_eq "$(printf '%s\n' "$OUT" | grep -cE '^~~~~$')" 0 "no fence at column 0"
assert_eq "$(printf '%s\n' "$OUT" | grep -cE '^  ~~~+$')" 2 "open and close fences are indented"
assert_contains "$OUT" '  line two' "content lines are indented"

echo "renderer: failed files are listed"
new_sandbox
fixture_minimal '{"status":"complete","comments":[],
  "manifest":{"input":{},"coverage":{"selected":[],"completed":[],
    "failed":[{"path":"big.py"},{"path":"small.py"}],"waived":[],"reused":[]}}}'
render
assert_contains "$OUT" '- **Failed files:** big.py, small.py' "failed files listed"

echo "renderer: a run with no review.json renders the gap, not a usage error"
new_sandbox
mkdir -p "$WS/failed-run"
OUT="$("$RENDER" "$WS/failed-run" 2>&1)"; RC=$?
assert_eq "$RC" 0 "exits 0"
assert_contains "$OUT" '- **Status:** `missing`. The run produced no review output.' "a failed run reads as the gap it is"
OUT="$("$RENDER" "$WS/nope" 2>&1)"; RC=$?
assert_eq "$RC" 2 "a missing directory is still a usage error"

make_stub() {
  stub="$WS/stub"
  mkdir -p "$stub"
  cat >"$stub/ocr" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
out=""
args=("$@")
for ((i = 0; i < $#; i++)); do
  if [[ "${args[$i]}" == "--output" ]]; then out="${args[$((i + 1))]}"; fi
done
if [[ -n "$STUB_EXIT" ]]; then exit "$STUB_EXIT"; fi
printf '{"status":"complete","session_id":"abc-123","comments":[]}' >"$out"
STUB
  chmod +x "$stub/ocr"
  export STUB_LOG="$WS/args.txt"
  export STUB_EXIT=""
  : >"$STUB_LOG"
}

echo "wrapper: range mode passes the range, brief and provenance"
new_sandbox
make_stub
mkdir -p "$WS/repo" "$WS/out"
printf 'make add safe\n' >"$WS/brief.md"
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out "$WS/out" --brief "$WS/brief.md" --base aaa --head bbb
assert_eq "$?" 0 "exits 0"
assert_contains "$(cat "$WS/args.txt")" 'review --format json' "invokes ocr review"
assert_contains "$(cat "$WS/args.txt")" "--from aaa --to bbb" "passes the range"
assert_contains "$(cat "$WS/args.txt")" "--background-file" "passes the brief"
assert_contains "$(cat "$WS/out/cmd.txt")" 'ocr review' "records the tool invocation"
assert_contains "$(cat "$WS/out/cmd.txt")" '--from aaa --to bbb' "records the range"
assert_eq "$(cat "$WS/out/session.txt")" "abc-123" "extracts the session id"

echo "wrapper: commit mode passes the commit"
new_sandbox
make_stub
mkdir -p "$WS/repo" "$WS/out"
: >"$STUB_LOG"
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out "$WS/out" --commit c946c58
assert_contains "$(cat "$WS/args.txt")" "--commit c946c58" "passes the commit"
assert_not_contains "$(cat "$WS/args.txt")" "--from" "no range in commit mode"

echo "wrapper: an ocr failure propagates and is recorded"
new_sandbox
make_stub
STUB_EXIT=3
mkdir -p "$WS/repo" "$WS/out"
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out "$WS/out" --commit x >/dev/null 2>&1
rc=$?
assert_eq "$rc" 3 "propagates ocr's exit code"
assert_eq "$(cat "$WS/out/exit.txt")" "3" "records the code"

echo "wrapper: a missing brief is a usage error, not a silent review"
new_sandbox
make_stub
mkdir -p "$WS/repo" "$WS/out"
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out "$WS/out" --brief "$WS/nope.md" --commit x >/dev/null 2>&1
rc=$?
assert_eq "$rc" 2 "usage error exits 2"
assert_not_contains "$(cat "$WS/args.txt")" "review" "never invoked the tool"

echo "wrapper: an option without its value is a usage error, not a crash"
new_sandbox
make_stub
mkdir -p "$WS/repo"
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out >/dev/null 2>&1
rc=$?
assert_eq "$rc" 2 "missing value exits 2 via usage"

echo "wrapper: relative out and brief paths are rejected before the cd"
new_sandbox
make_stub
mkdir -p "$WS/repo" "$WS/out"
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out out --commit x >/dev/null 2>&1
rc1=$?
PATH="$WS/stub:$PATH" "$REVIEW" --repo "$WS/repo" --out "$WS/out" --brief brief.md --commit x >/dev/null 2>&1
rc2=$?
assert_eq "$rc1" 2 "relative out rejected"
assert_eq "$rc2" 2 "relative brief rejected"
assert_not_contains "$(cat "$WS/args.txt")" "review" "never invoked the tool"

SCAN="$TOOLS/executable_scan.sh"
scan() { # body text -> OUT, RC, BODY (the file after the scan)
  printf '%s\n' "$1" >"$WS/body.md"
  OUT="$(HOME=/Users/someone "$SCAN" "$WS/body.md" 2>&1)"; RC=$?
  BODY="$(cat "$WS/body.md")"
}

echo "scan: a clean body passes untouched"
new_sandbox
scan 'Review round 1: no issues found.'
assert_eq "$RC" 0 "exits 0"
assert_eq "$BODY" 'Review round 1: no issues found.' "body untouched"

echo "scan: the home path becomes ~ and passes"
new_sandbox
scan 'see /Users/someone/src/app/main.py:4'
assert_eq "$RC" 0 "exits 0"
assert_eq "$BODY" 'see ~/src/app/main.py:4' "home redacted in place"

echo "scan: provider keys with inner hyphens are caught"
for key in sk-ant-api03-AbCdEfGhIjKlMnOpQrStUv sk-proj-AbCdEfGhIjKlMnOpQrStUv sk-AbCdEfGhIjKlMnOpQrStUv; do
  new_sandbox
  scan "leaked $key here"
  assert_eq "$RC" 1 "blocks ${key%%-A*}"
  assert_contains "$OUT" "1:leaked $key here" "prints the hit line for ${key%%-A*}"
done

echo "scan: other token formats are caught"
# The fakes are assembled at runtime so the source holds no token-shaped
# literal for the repo's own secret scanner to flag.
b=AbCdEfGhIjKlMnOpQrStUvWx up=ABCDEFGHIJKLMNOP key="PRIVATE KEY"
for tok in "ghp_${b}012345" "github_pat_11${b}" "AKIA${up}" \
  "xoxb-${up}-abcdef" "glpat-${b}" "npm_${b}" \
  "-----BEGIN OPENSSH ${key}-----" "Authorization: Bearer eyJ${b}.abcdef"; do
  new_sandbox
  scan "x $tok"
  assert_eq "$RC" 1 "blocks ${tok:0:12}"
done

echo "scan: other home and temp paths are caught"
for p in /Users/other/x /home/other/x /private/tmp/x /var/folders/ab/x \
  /tmp/agent-scratch-9f2/x /root/.ssh/id_ed25519 /run/user/1000/x; do
  new_sandbox
  scan "at $p"
  assert_eq "$RC" 1 "blocks $p"
done

echo "scan: ordinary code under review is not a leak"
new_sandbox
scan 'the owner someone/repo serves http://localhost:3000 on 127.0.0.1; a bearer token check; grep -E "/Users/|/home/|sk-[A-Za-z0-9_-]{20,}"; docs that name the /tmp/ prefix, /root/ usage, and /run/user/ ids'
assert_eq "$RC" 0 "exits 0"

echo "scan: no file is a usage error"
new_sandbox
OUT="$("$SCAN" "$WS/nope.md" 2>&1)"; RC=$?
assert_eq "$RC" 2 "usage error exits 2"

BRANCH="$TOOLS/executable_branch-name.sh"
branch() { # stdin text, args -> OUT, RC
  OUT="$("$BRANCH" "$@" 2>&1)"; RC=$?
}

echo "branch-name: slug and hash follow the documented rule"
branch --type gh --locator 'owner/repo#12' --title 'Fix: the Thing (v2)!' <<<'Fix the thing'
assert_eq "$RC" 0 "exits 0"
assert_eq "$OUT" "loop/gh-fix-the-thing-v2-e29971a8" "slug lowercased and hyphenated, hash over locator, newline, text"

echo "branch-name: trailing newlines in the item text do not re-key"
OUT1="$(printf 'Fix the thing\n\n\n' | "$BRANCH" --type gh --locator 'owner/repo#12' --title t)"
OUT2="$(printf 'Fix the thing' | "$BRANCH" --type gh --locator 'owner/repo#12' --title t)"
assert_eq "$OUT1" "$OUT2" "same name either way"

echo "branch-name: an edited source re-keys the hash"
OUT1="$("$BRANCH" --type md --locator 'todo.md:4' --title t <<<'one')"
OUT2="$("$BRANCH" --type md --locator 'todo.md:4' --title t <<<'two')"
assert_eq "$([[ "$OUT1" != "$OUT2" ]] && printf differ || printf same)" "differ" "different hash"

echo "branch-name: a long or symbol-only title stays a valid ref"
branch --type html --locator 'a.html#x' --title "$(printf 'word %.0s' {1..20})" <<<'x'
slug="${OUT#loop/html-}"; slug="${slug%-*}"
assert_eq "$([[ ${#slug} -le 40 && "$slug" != *- ]] && printf ok || printf "bad:$slug")" "ok" "slug capped at 40, no trailing hyphen"
branch --type html --locator 'a.html#x' --title '!!!' <<<'x'
assert_contains "$OUT" "loop/html-task-" "empty slug falls back to task"

echo "branch-name: an unknown source type is a usage error"
branch --type jira --locator x --title t <<<'x'
assert_eq "$RC" 2 "usage error exits 2"

PRR="$TOOLS/executable_pr-round.sh"

make_pr_round_env() {
  stub="$WS/stubbin"
  mkdir -p "$stub"
  cat >"$stub/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") printf '%s\n' "$GH_PR_JSON" ;;
  "repo view") printf 'test-owner/test-repo\n' ;;
  *) exit 64 ;;
esac
GHSTUB
  cat >"$stub/ocr" <<'OCRSTUB'
#!/usr/bin/env bash
out=""; mode="range"; csha=""
args=("$@")
for ((i = 0; i < $#; i++)); do
  case "${args[$i]}" in
    --output) out="${args[$((i + 1))]}" ;;
    --from) mode="range" ;;
    --commit) mode="commit"; csha="${args[$((i + 1))]}" ;;
  esac
done
if [[ "$mode" == "commit" && -n "$STUB_FAIL_ON_COMMIT" && "$csha" == "$STUB_FAIL_ON_COMMIT" ]]; then
  exit 3
fi
status="$STUB_RANGE_STATUS"
if [[ "$mode" == "commit" ]]; then status="$STUB_COMMIT_STATUS"; fi
printf '{"status":"%s","session_id":"stub-session","comments":[],"summary":{"total_tokens":%s}}' "$status" "${STUB_TOKENS:-0}" >"$out"
OCRSTUB
  chmod +x "$stub/gh" "$stub/ocr"
  export STUB_RANGE_STATUS=complete STUB_COMMIT_STATUS=complete STUB_FAIL_ON_COMMIT=""
}

make_fixture_repo() {
  origin="$WS/origin.git"
  repo="$WS/repo"
  git init -q --bare "$origin"
  git init -q "$repo"
  git -C "$repo" config user.email t@t.local
  git -C "$repo" config user.name test
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" remote add origin "$origin"
  printf 'a\n' >"$repo/f.txt"
  git -C "$repo" add f.txt
  git -C "$repo" commit -qm base
  FR_BASE=$(git -C "$repo" rev-parse HEAD)
  printf 'b\n' >"$repo/f.txt"
  git -C "$repo" commit -qam second
  FR_HEAD=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" push -q origin "$FR_BASE:refs/heads/main" "HEAD:refs/pull/39/head"
  export GH_PR_JSON='{"state":"OPEN","baseRefName":"main","headRefOid":"'"$FR_HEAD"'","headRefName":"loop/x-y-abc12345","url":"https://example.test/39"}'
}

run_prr() {
  (
    HOME="$WS/home"
    export HOME
    mkdir -p "$HOME"
    PATH="$stub:$PATH" "$PRR" "$@"
  )
}

echo "pr-round: a completed range run records one run"
new_sandbox
make_pr_round_env
make_fixture_repo
out=$(run_prr --repo "$repo" --pr 39 --round 1 --expect-branch loop/x-y-abc12345)
rd="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1"
assert_eq "$out" "$rd" "prints the round dir"
assert_json '.reviewer_complete == true' "$rd/round.json" "reviewer_complete true"
assert_eq "$(jq '.runs | length' "$rd/round.json")" 1 "one run"
assert_eq "$(jq -r '.runs[0].mode' "$rd/round.json")" "range" "range mode"
assert_eq "$(jq -r '.range.head' "$rd/round.json")" "$FR_HEAD" "range head recorded"
assert_eq "$(jq -r '.range.base' "$rd/round.json")" "$FR_BASE" "range base is the resolved base SHA"
assert_eq "$(jq -r '.range.exact' "$rd/round.json")" "$FR_BASE..$FR_HEAD" "exact is sha..sha"
assert_eq "$(jq -r '.range.base_branch' "$rd/round.json")" "main" "the base branch name is kept"
assert_eq "$(jq -r '.identity.head_branch' "$rd/round.json")" "loop/x-y-abc12345" "identity recorded"

echo "pr-round: a skipped range retries per commit and recovers"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_RANGE_STATUS=skipped STUB_COMMIT_STATUS=complete
out=$(run_prr --repo "$repo" --pr 39 --round 1)
rd="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1"
assert_json '.reviewer_complete == true' "$rd/round.json" "reviewer_complete true after the commit retry"
assert_eq "$(jq '.runs | length' "$rd/round.json")" 2 "range plus one commit run"
assert_eq "$(jq -r '.runs[0].status' "$rd/round.json")" "skipped" "the skip is recorded verbatim"

echo "pr-round: an all-skipped round is reviewer_complete false"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_RANGE_STATUS=skipped STUB_COMMIT_STATUS=skipped
out=$(run_prr --repo "$repo" --pr 39 --round 1)
rd="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1"
assert_json '.reviewer_complete == false' "$rd/round.json" "reviewer_complete false"
assert_eq "$(jq '.runs | length' "$rd/round.json")" 2 "both runs recorded"

echo "pr-round: a partial per-commit recovery is reviewer_complete false"
new_sandbox
make_pr_round_env
make_fixture_repo
printf 'c\n' >"$repo/f.txt"
git -C "$repo" commit -qam third
FR_HEAD3=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" push -q origin "HEAD:refs/pull/39/head"
export GH_PR_JSON='{"state":"OPEN","baseRefName":"main","headRefOid":"'"$FR_HEAD3"'","headRefName":"loop/x-y-abc12345","url":"https://example.test/39"}'
export STUB_RANGE_STATUS=skipped STUB_COMMIT_STATUS=complete STUB_FAIL_ON_COMMIT="$FR_HEAD"
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
rd="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1"
assert_json '.reviewer_complete == false' "$rd/round.json" "one unreviewed commit keeps the round incomplete"
assert_eq "$(jq '.runs | length' "$rd/round.json")" 3 "range plus two commit runs"
assert_eq "$(jq -r '.runs[2].status' "$rd/round.json")" "missing" "the failed retry is recorded verbatim"

echo "pr-round: an identity mismatch stops before anything runs"
new_sandbox
make_pr_round_env
make_fixture_repo
out=$(run_prr --repo "$repo" --pr 39 --round 1 --expect-branch loop/someone-else 2>/dev/null)
rc=$?
assert_eq "$rc" 3 "identity mismatch exits 3"
assert_eq "$([[ -d "$WS/home/.cache/pr-loop" ]] && printf yes || printf no)" "no" "no round dir created"

echo "pr-round: a non-open PR is refused"
new_sandbox
make_pr_round_env
make_fixture_repo
export GH_PR_JSON='{"state":"MERGED","baseRefName":"main","headRefOid":"x","headRefName":"y","url":"z"}'
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null 2>&1
rc=$?
assert_eq "$rc" 4 "merged PR exits 4"

echo "pr-round: a second invocation into the same round is refused"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null 2>&1
rc=$?
assert_eq "$rc" 6 "second invocation exits 6 without --rerun"
assert_eq "$(jq -r '.cumulative_tokens' "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1/round.json")" "100" "the first run's evidence is intact"

echo "pr-round: --rerun supersedes instead of clobbering"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
export STUB_TOKENS=250
out=$(run_prr --repo "$repo" --pr 39 --round 1 --rerun)
rd="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1"
assert_eq "$(find "$rd" -maxdepth 2 -name round.json | wc -l | tr -d ' ')" 2 "old and new round.json both exist"
assert_json '.cumulative_tokens == 250' "$rd/round.json" "the fresh round.json is the active one"
assert_json '.summary.total_tokens == 100' "$rd"/superseded-*/review.json "the superseded evidence is retained"

echo "pr-round: cumulative tokens span rounds"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
export STUB_TOKENS=250
run_prr --repo "$repo" --pr 39 --round 2 >/dev/null
rd2="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-2"
assert_json '.round_tokens == 250 and .cumulative_tokens == 350' "$rd2/round.json" "round 2 cumulative is 350 across both rounds"

echo "pr-round: a zero-padded round still counts toward the cumulative cost"
new_sandbox
make_pr_round_env
make_fixture_repo
rdp="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-08"
mkdir -p "$rdp"
printf '{"round_tokens":50}' >"$rdp/round.json"
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 9 >/dev/null
assert_json '.cumulative_tokens == 150' "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-9/round.json" "round 08 is counted"

echo "pr-round: the recorded base does not move when main advances"
new_sandbox
make_pr_round_env
make_fixture_repo
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
prev_branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
git -C "$repo" checkout -q "$FR_BASE"
printf 'm\n' >"$repo/g.txt"
git -C "$repo" add g.txt
git -C "$repo" commit -qm "on main"
git -C "$repo" push -q origin HEAD:refs/heads/main
git -C "$repo" checkout -q "$prev_branch"
run_prr --repo "$repo" --pr 39 --round 2 >/dev/null
b1=$(jq -r '.range.base' "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1/round.json")
b2=$(jq -r '.range.base' "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-2/round.json")
assert_eq "$b2" "$b1" "the same head records the same base"
assert_eq "$b1" "$FR_BASE" "the base is the merge base, not the tip"

echo "pr-round: leftovers from an interrupted run are never read as this run's evidence"
new_sandbox
make_pr_round_env
make_fixture_repo
rd="$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1"
mkdir -p "$rd"
printf '{"status":"complete","summary":{"total_tokens":999}}' >"$rd/review.json"
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null 2>&1
rc=$?
assert_eq "$rc" 6 "a round dir holding leftovers is refused without --rerun"
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 1 --rerun >/dev/null
assert_json '.cumulative_tokens == 100' "$rd/round.json" "the fresh run is the only evidence counted"
assert_json '.summary.total_tokens == 999' "$rd"/superseded-*/review.json "the leftover is kept aside"

echo "pr-round: a rerun of an earlier round counts only rounds before it"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
export STUB_TOKENS=250
run_prr --repo "$repo" --pr 39 --round 2 >/dev/null
export STUB_TOKENS=50
run_prr --repo "$repo" --pr 39 --round 1 --rerun >/dev/null
assert_json '.cumulative_tokens == 50' "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1/round.json" "round 2 is not to date for round 1"

echo "pr-round: a failed fetch supersedes nothing and exits 5"
new_sandbox
make_pr_round_env
make_fixture_repo
export STUB_TOKENS=100
run_prr --repo "$repo" --pr 39 --round 1 >/dev/null
git -C "$repo" remote set-url origin "$WS/nowhere.git"
run_prr --repo "$repo" --pr 39 --round 1 --rerun >/dev/null 2>&1
rc=$?
assert_eq "$rc" 5 "an unresolvable origin exits 5"
assert_json '.cumulative_tokens == 100' "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1/round.json" "the prior evidence is untouched"
assert_eq "$(find "$WS/home/.cache/pr-loop/test-owner/test-repo/pr-39/round-1" -maxdepth 1 -name 'superseded-*' | wc -l | tr -d ' ')" 0 "nothing was superseded"

echo "pr-round: a fork PR with the loop's branch name fails the identity check"
new_sandbox
make_pr_round_env
make_fixture_repo
export GH_PR_JSON="$(jq -c '.isCrossRepository = true' <<<"$GH_PR_JSON")"
run_prr --repo "$repo" --pr 39 --round 1 --expect-branch loop/x-y-abc12345 >/dev/null 2>&1
rc=$?
assert_eq "$rc" 3 "cross-repository head exits 3"

report
