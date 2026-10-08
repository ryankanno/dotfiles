#!/usr/bin/env bash
# Black-box tests for review-range.py. Mocks only the external boundary,
# the roborev CLI.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../dot_claude/scripts/executable_review-range.py"
PYTHON="$(python3 -c 'import sys; print(sys.executable)')"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1" >&2; }
assert_eq() { [[ "$1" == "$2" ]] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
assert_contains() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 (expected to contain: $2)";; esac; }

# Fake roborev: `list ... --repo <dir>` prints $WS/list.json and records the
# arguments; `config get server_addr` prints $WS/addr. The daemon API is a real
# stdlib http.server over $WS/http, which ignores the query string, so
# /api/jobs?id=N serves $WS/http/api/jobs.
new_sandbox() {
  stop_server
  [[ -n "${WS:-}" ]] && rm -rf "$WS"
  WS="$(mktemp -d)" && [[ -n "$WS" ]] || { echo "cannot create sandbox" >&2; exit 1; }
  WS="$(cd "$WS" && pwd -P)"
  mkdir -p "$WS/bin" "$WS/wt" "$WS/other" "$WS/ci/roborev-ci-14399-2206444493" "$WS/http/api"
  echo '[]' >"$WS/list.json"
  echo "127.0.0.1:1" >"$WS/addr"
  cat >"$WS/bin/roborev" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "list "*) echo "$*" >"$WS/list-args"
    [[ -f "$WS/list-fails" ]] && { echo "list: daemon not running" >&2; exit 1; }
    cat "$WS/list.json";;
  "config get") [[ "$3" == server_addr ]] && cat "$WS/addr";;
  *) echo "fake roborev: unexpected call: $*" >&2; exit 64;;
esac
FAKE
  chmod +x "$WS/bin/roborev"
  export WS
}
SERVER_PID=""
start_server() { # serves $WS/http and points the fake's server_addr at it
  local port
  port=$("$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
  "$PYTHON" -m http.server "$port" --bind 127.0.0.1 --directory "$WS/http" >/dev/null 2>&1 &
  SERVER_PID=$!
  echo "127.0.0.1:$port" >"$WS/addr"
  for _ in $(seq 50); do
    curl -s "http://127.0.0.1:$port/" >/dev/null && return
    sleep 0.1
  done
  echo "test http server did not start" >&2; exit 1
}
# The wait reaps the server, so bash 3.2 prints no "Terminated" notice for it.
stop_server() { [[ -n "$SERVER_PID" ]] && { kill "$SERVER_PID"; wait "$SERVER_PID"; } 2>/dev/null; SERVER_PID=""; }
trap 'stop_server; [[ -n "${WS:-}" ]] && rm -rf "$WS"' EXIT

run() { # dir
  OUT="$(PATH="$WS/bin:$PATH" "$PYTHON" "$SCRIPT" "$1" 2>"$WS/stderr")"
  RC=$?
  ERR="$(cat "$WS/stderr")"
}

echo "a CI worktree names its job, which the daemon returns while it runs"
new_sandbox
jq -n '{jobs:[{id:7,status:"running",git_ref:"zzz..yyy"},{id:14399,status:"running",git_ref:"aaa..bbb"}]}' >"$WS/http/api/jobs"
start_server
run "$WS/ci/roborev-ci-14399-2206444493"
assert_eq "$RC" 0 "exits 0"
assert_eq "$OUT" $'14399\taaa..bbb' "prints the job id and its range"

echo "a CI worktree whose job the daemon does not return is an error"
new_sandbox
jq -n '{jobs:[]}' >"$WS/http/api/jobs"
start_server
run "$WS/ci/roborev-ci-14399-2206444493"
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_contains "$ERR" "job 14399" "says which job"

echo "an unreachable daemon is an error, not a guess"
new_sandbox
run "$WS/ci/roborev-ci-14399-2206444493"
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_eq "$OUT" "" "prints no range"

echo "a unix-socket daemon address is reported as unsupported"
new_sandbox
echo "unix:///tmp/roborev.sock" >"$WS/addr"
run "$WS/ci/roborev-ci-14399-2206444493"
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_contains "$ERR" "unix" "says why"

echo "one active job in the worktree gives its range"
new_sandbox
jq -n --arg wt "$WS/wt" --arg other "$WS/other" '[
  {id:10,status:"queued",panel_role:"synthesis",git_ref:"aaa..bbb",worktree_path:$wt,repo_path:$other},
  {id:9,status:"done",git_ref:"old..old",worktree_path:$wt,repo_path:$other},
  {id:8,status:"running",git_ref:"ccc..ddd",worktree_path:$other,repo_path:$other}]' >"$WS/list.json"
run "$WS/wt"
assert_eq "$RC" 0 "exits 0"
assert_eq "$OUT" $'10\taaa..bbb' "ignores finished jobs and other worktrees"
assert_contains "$(cat "$WS/list-args")" "--all-branches" "lists every branch"
assert_contains "$(cat "$WS/list-args")" "--json" "asks for JSON"
assert_contains "$(cat "$WS/list-args")" "--repo $WS/wt" "scopes the list to the directory"

echo "a job without a worktree matches on its repo path"
new_sandbox
jq -n --arg wt "$WS/wt" '[{id:11,status:"running",git_ref:"eee",worktree_path:"",repo_path:$wt}]' >"$WS/list.json"
run "$WS/wt"
assert_eq "$OUT" $'11\teee' "matches the repo root"

echo "a path given through a symlink still matches"
new_sandbox
ln -s "$WS/wt" "$WS/link"
jq -n --arg wt "$WS/wt" '[{id:12,status:"running",git_ref:"aaa..bbb",worktree_path:$wt,repo_path:"/r"}]' >"$WS/list.json"
run "$WS/link"
assert_eq "$OUT" $'12\taaa..bbb' "resolves both sides"

echo "two active jobs on the same range agree"
new_sandbox
jq -n --arg wt "$WS/wt" '[
  {id:14,status:"queued",git_ref:"aaa..bbb",worktree_path:$wt,repo_path:"/r"},
  {id:13,status:"running",git_ref:"aaa..bbb",worktree_path:$wt,repo_path:"/r"}]' >"$WS/list.json"
run "$WS/wt"
assert_eq "$RC" 0 "exits 0"
assert_eq "$OUT" $'14\taaa..bbb' "names the newest job"

echo "two active jobs on different ranges are ambiguous"
new_sandbox
jq -n --arg wt "$WS/wt" '[
  {id:14,status:"queued",git_ref:"aaa..bbb",worktree_path:$wt,repo_path:"/r"},
  {id:13,status:"running",git_ref:"ccc",worktree_path:$wt,repo_path:"/r"}]' >"$WS/list.json"
run "$WS/wt"
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_contains "$ERR" "aaa..bbb" "names both ranges"
assert_contains "$ERR" "ccc" "names both ranges"

echo "no active job is reported, not guessed"
new_sandbox
run "$WS/wt"
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_contains "$ERR" "no queued or running roborev job" "says why"
assert_eq "$OUT" "" "prints no range"

echo "a failing roborev list is an error, not a guess"
new_sandbox
touch "$WS/list-fails"
run "$WS/wt"
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"
assert_contains "$ERR" "daemon not running" "passes on the CLI's error"
assert_eq "$OUT" "" "prints no range"

echo "no directory is a usage error"
new_sandbox
OUT="$(PATH="$WS/bin:$PATH" "$PYTHON" "$SCRIPT" 2>/dev/null)"; RC=$?
assert_eq "$([[ $RC -ne 0 ]] && echo nonzero)" nonzero "exits non-zero"

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
