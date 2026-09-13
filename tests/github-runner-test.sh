#!/usr/bin/env bash
# Black-box tests for runner.sh. Mocks only the external boundaries:
#   gh  -> network/API        tar/config.sh/svc.sh -> the runner package
# Everything else (arg parsing, folder naming, target derivation, control
# flow) runs for real against a temp GITHUB_RUNNERS_DIR.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/executable_github-runner.sh"

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
assert_dir() { [[ -d "$1" ]] && ok "$2" || bad "$2 (dir missing: $1)"; }
assert_nodir(){ [[ ! -e "$1" ]] && ok "$2" || bad "$2 (dir still exists: $1)"; }

# Build a fresh sandbox: temp base dir, fake bin on PATH, seeded cache.
# Sets globals WS, GH_LOG, PKG_LOG and exports env for runner.sh.
new_sandbox() { # [owner-type]  default Organization
  WS="$(mktemp -d)"
  export GITHUB_RUNNERS_DIR="$WS/runners"
  export GH_LOG="$WS/gh.log"
  export PKG_LOG="$WS/pkg.log"
  : >"$GH_LOG"; : >"$PKG_LOG"
  export OWNER_TYPE="${1:-Organization}"

  # Seed the tarball cache so ensure_tarball never reaches the network.
  echo "dummy" >"$WS/seed.tgz"
  export RUNNER_TARBALL_SEED="$WS/seed.tgz"

  local fakebin="$WS/bin"
  mkdir -p "$fakebin"

  cat >"$fakebin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >>"$GH_LOG"
[[ "$1 $2" == "auth status" ]] && exit 0
case "$*" in
  *"/users/"*)                echo "${OWNER_TYPE}";;
  *registration-token*)       echo "FAKETOKEN";;
  *"/actions/runners --paginate"*) printf '%s\n' "alpha	online	false	self-hosted" "beta	offline	false	self-hosted,gpu";;
esac
exit 0
GH

  cat >"$fakebin/tar" <<'TAR'
#!/usr/bin/env bash
# Emulate extracting the runner package: drop logging config.sh/svc.sh stubs
# into the -C target directory.
dir=""; prev=""
for a in "$@"; do
  [[ "$prev" == "-C" ]] && dir="$a"
  prev="$a"
done
[[ -n "$dir" ]] || exit 0
for s in config.sh svc.sh; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s"\n' "$s" "$PKG_LOG" >"$dir/$s"
  chmod +x "$dir/$s"
done
TAR

  # svc.sh runs under sudo on Linux, so the sandbox needs its own sudo that
  # just drops the prefix. systemctl is stubbed too: nothing here may reach
  # the host's real actions.runner.* units.
  printf '#!/usr/bin/env bash\nexec "$@"\n' >"$fakebin/sudo"
  cat >"$fakebin/systemctl" <<SYSCTL
#!/usr/bin/env bash
echo "systemctl \$*" >>"\$PKG_LOG"
SYSCTL

  chmod +x "$fakebin/gh" "$fakebin/tar" "$fakebin/sudo" "$fakebin/systemctl"
  export PATH="$fakebin:$PATH"
}

drop_sandbox() { unset OWNER_TYPE; rm -rf "$WS"; }

run_runner() { # runs runner.sh, captures stdout+stderr in OUT, exit in RC
  OUT="$(bash "$SCRIPT" "$@" 2>&1)"; RC=$?
}

# ---------------------------------------------------------------------------

test_add_repo() {
  echo "test_add_repo"
  new_sandbox
  run_runner add acme widget --labels smoke
  assert_eq "$RC" "0" "exits 0"
  assert_dir "$GITHUB_RUNNERS_DIR/actions-runner-acme-widget" "folder created"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "--url https://github.com/acme/widget" "config uses repo url"
  assert_contains "$pkg" "--name actions-runner-acme-widget" "name = folder"
  assert_contains "$pkg" "--token FAKETOKEN" "config gets token"
  assert_contains "$pkg" "--labels smoke" "custom label passed"
  assert_contains "$pkg" "svc.sh install" "service installed"
  assert_contains "$pkg" "svc.sh start" "service started"
  local gh; gh="$(cat "$GH_LOG")"
  assert_contains "$gh" "api -X POST /repos/acme/widget/actions/runners/registration-token" "repo reg-token endpoint"
  drop_sandbox
}

test_add_org() {
  echo "test_add_org"
  new_sandbox
  run_runner add acme
  assert_eq "$RC" "0" "exits 0"
  assert_dir "$GITHUB_RUNNERS_DIR/actions-runner-acme" "org folder created"
  local pkg gh; pkg="$(cat "$PKG_LOG")"; gh="$(cat "$GH_LOG")"
  assert_contains "$pkg" "--url https://github.com/acme " "config uses org url"
  assert_contains "$pkg" "--name actions-runner-acme" "org name = folder"
  assert_contains "$gh" "api -X POST /orgs/acme/actions/runners/registration-token" "org reg-token endpoint"
  drop_sandbox
}

test_add_user_no_repo_fails() {
  echo "test_add_user_no_repo_fails"
  new_sandbox User
  run_runner add alice
  [[ "$RC" -ne 0 ]] && ok "nonzero exit" || bad "should fail for user + no repo"
  assert_contains "$OUT" "personal accounts need a repo" "explains the failure"
  assert_nodir "$GITHUB_RUNNERS_DIR/actions-runner-alice" "no folder created"
  drop_sandbox
}

test_add_collision_suffix() {
  echo "test_add_collision_suffix"
  new_sandbox
  # Simulate a repo that already has a runner folder.
  mkdir -p "$GITHUB_RUNNERS_DIR/actions-runner-acme-widget"
  run_runner add acme widget
  assert_eq "$RC" "0" "first add exits 0"
  assert_dir "$GITHUB_RUNNERS_DIR/actions-runner-acme-widget-1" "appends -1"
  run_runner add acme widget
  assert_eq "$RC" "0" "second add exits 0"
  assert_dir "$GITHUB_RUNNERS_DIR/actions-runner-acme-widget-2" "appends -2"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "--name actions-runner-acme-widget-2" "name follows suffixed folder"
  drop_sandbox
}

test_remove_repo() {
  echo "test_remove_repo"
  new_sandbox
  local folder="actions-runner-acme-widget"
  local dir="$GITHUB_RUNNERS_DIR/$folder"
  mkdir -p "$dir"
  cat >"$dir/.runner" <<'EOF'
{ "agentId": 42, "agentName": "actions-runner-acme-widget",
  "gitHubUrl": "https://github.com/acme/widget" }
EOF
  printf '#!/usr/bin/env bash\necho "svc.sh $*" >>"%s"\n' "$PKG_LOG" >"$dir/svc.sh"
  chmod +x "$dir/svc.sh"

  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  local gh pkg; gh="$(cat "$GH_LOG")"; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "svc.sh stop" "service stopped"
  assert_contains "$pkg" "svc.sh uninstall" "service uninstalled"
  assert_contains "$gh" "api -X DELETE /repos/acme/widget/actions/runners/42" "deregister by id"
  assert_nodir "$dir" "folder deleted"
  drop_sandbox
}

test_remove_half_built() {
  echo "test_remove_half_built"
  new_sandbox
  local folder="actions-runner-acme-broken"
  local dir="$GITHUB_RUNNERS_DIR/$folder"
  mkdir -p "$dir"   # no .runner
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  local gh; gh="$(cat "$GH_LOG")"
  assert_not_contains "$gh" "DELETE" "no API delete without .runner"
  assert_contains "$OUT" "half-built" "warns half-built"
  assert_nodir "$dir" "folder deleted"
  drop_sandbox
}

test_list_org() {
  echo "test_list_org"
  new_sandbox
  run_runner list acme
  assert_eq "$RC" "0" "exits 0"
  assert_contains "$OUT" "NAME	STATUS	BUSY	LABELS" "prints header"
  assert_contains "$OUT" "alpha" "lists alpha"
  assert_contains "$OUT" "beta" "lists beta"
  local gh; gh="$(cat "$GH_LOG")"
  assert_contains "$gh" "api /orgs/acme/actions/runners --paginate" "org runners endpoint"
  drop_sandbox
}

test_list_repo() {
  echo "test_list_repo"
  new_sandbox
  run_runner list acme widget
  assert_eq "$RC" "0" "exits 0"
  local gh; gh="$(cat "$GH_LOG")"
  assert_contains "$gh" "api /repos/acme/widget/actions/runners --paginate" "repo runners endpoint"
  drop_sandbox
}

test_list_user_no_repo_fails() {
  echo "test_list_user_no_repo_fails"
  new_sandbox User
  run_runner list alice
  [[ "$RC" -ne 0 ]] && ok "nonzero exit" || bad "should fail for user + no repo"
  assert_contains "$OUT" "work per repo" "explains the failure"
  drop_sandbox
}

test_api_target_from_url() {
  echo "test_api_target_from_url"
  local got
  # shellcheck source=executable_github-runner.sh
  got="$(source "$SCRIPT"; api_target_from_url "https://github.com/acme")"
  assert_eq "$got" "orgs/acme" "org url -> orgs/acme"
  # shellcheck source=executable_github-runner.sh
  got="$(source "$SCRIPT"; api_target_from_url "https://github.com/acme/widget")"
  assert_eq "$got" "repos/acme/widget" "repo url -> repos/acme/widget"
  # shellcheck source=executable_github-runner.sh
  got="$(source "$SCRIPT"; api_target_from_url "https://github.com/acme/widget/")"
  assert_eq "$got" "repos/acme/widget" "trailing slash trimmed"
}

test_add_repo
test_add_org
test_add_user_no_repo_fails
test_add_collision_suffix
test_remove_repo
test_remove_half_built
test_list_org
test_list_repo
test_list_user_no_repo_fails
test_api_target_from_url

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
