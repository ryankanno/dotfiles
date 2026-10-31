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

  # Seed the tarball cache so ensure_tarball never reaches the network. The
  # release stub publishes the seed's digest, so add verifies by default.
  # openssl, not the script's tools, computes the digest the script must match.
  echo "dummy" >"$WS/seed.tgz"
  export RUNNER_TARBALL_SEED="$WS/seed.tgz"
  export RUNNER_VERSION="9.9.9" RUNNER_ARCH="test-arch"
  export TARBALL_NAME="actions-runner-$RUNNER_ARCH-$RUNNER_VERSION.tar.gz"
  export RELEASE_JSON="$WS/release.json"
  write_release "\"sha256:$(openssl dgst -sha256 -r "$WS/seed.tgz" | cut -d' ' -f1)\""

  # Every test but the *_linux ones takes the macOS paths, whatever the host.
  export UNAME_S="Darwin" UNAME_M="arm64"

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
  *"releases/tags/v$RUNNER_VERSION"*) [[ -f "$RELEASE_JSON" ]] || exit 1; cat "$RELEASE_JSON";;
  *"release download"*)       cp "$DOWNLOAD_SRC" "$GITHUB_RUNNERS_DIR/.cache/$TARBALL_NAME";;
esac
exit 0
GH

  cat >"$fakebin/uname" <<'UNAME'
#!/usr/bin/env bash
case "$1" in
  -s) echo "$UNAME_S";;
  -m) echo "$UNAME_M";;
esac
UNAME

  cat >"$fakebin/tar" <<'TAR'
#!/usr/bin/env bash
echo "tar $*" >>"$PKG_LOG"
# Emulate extracting the runner package: drop logging config.sh/svc.sh stubs
# into the -C target directory.
dir=""; file=""; prev=""
for a in "$@"; do
  [[ "$prev" == "-C" ]] && dir="$a"
  [[ "$prev" == "-xzf" ]] && file="$a"
  prev="$a"
done
[[ -n "$dir" ]] || exit 0
echo "tar-input $(cat "$file")" >>"$PKG_LOG"
for s in config.sh svc.sh; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s"\n' "$s" "$PKG_LOG" >"$dir/$s"
  chmod +x "$dir/$s"
done
TAR

  # The sandbox sudo logs its command so tests can see what ran as root, then
  # drops the prefix. It never runs rm, and systemctl is stubbed: nothing here
  # may reach the host's real actions.runner.* units.
  cat >"$fakebin/sudo" <<'SUDO'
#!/usr/bin/env bash
echo "sudo $*" >>"$PKG_LOG"
[[ "$1" == "rm" ]] && exit 0
exec "$@"
SUDO
  # STUB_UNIT and STUB_UNIT_DIR stand for a unit file in the systemd folder.
  cat >"$fakebin/systemctl" <<'SYSCTL'
#!/usr/bin/env bash
case "$1" in
  list-unit-files) [[ -z "${STUB_UNIT:-}" ]] || echo "$STUB_UNIT enabled enabled"; exit 0;;
  show)            echo "${STUB_UNIT_DIR:-}"; exit 0;;
esac
echo "systemctl $*" >>"$PKG_LOG"
SYSCTL

  chmod +x "$fakebin/gh" "$fakebin/tar" "$fakebin/sudo" "$fakebin/systemctl" "$fakebin/uname"
  export PATH="$fakebin:$PATH"
}

drop_sandbox() {
  unset OWNER_TYPE RUNNER_VERSION RUNNER_ARCH UNAME_S UNAME_M
  unset TARBALL_NAME RELEASE_JSON RUNNER_TARBALL_SEED STUB_UNIT STUB_UNIT_DIR
  rm -rf "$WS"
}

linux_host() { export UNAME_S="Linux" UNAME_M="x86_64"; }

write_release() { # digest as a JSON value; the release API's response body
  # The other asset comes first: only a match on the name finds the right digest.
  printf '{"assets":[{"name":"actions-runner-other.tar.gz","digest":"sha256:0"},{"name":"%s","digest":%s}]}\n' \
    "$TARBALL_NAME" "$1" >"$RELEASE_JSON"
}

run_runner() { # runs runner.sh, captures stdout+stderr in OUT, exit in RC
  OUT="$(bash "$SCRIPT" "$@" 2>&1)"; RC=$?
}

assert_add_refused() { # msg-needle label: add failed before it touched anything
  [[ "$RC" -ne 0 ]] && ok "$2: nonzero exit" || bad "$2: add should fail"
  assert_contains "$OUT" "$1" "$2: explains the failure"
  assert_nodir "$GITHUB_RUNNERS_DIR/actions-runner-acme-widget" "$2: no folder left behind"
  local pkg gh; pkg="$(cat "$PKG_LOG")"; gh="$(cat "$GH_LOG")"
  assert_not_contains "$pkg" "tar " "$2: nothing extracted"
  assert_not_contains "$gh" "registration-token" "$2: no registration token requested"
}

# A configured runner folder: .runner from the given JSON values, logging svc.sh.
seed_configured_runner() { # folder agentId-json gitHubUrl-json
  local dir="$GITHUB_RUNNERS_DIR/$1"
  mkdir -p "$dir"
  printf '{ "agentId": %s, "agentName": "%s", "gitHubUrl": %s }\n' "$2" "$1" "$3" >"$dir/.runner"
  printf '#!/usr/bin/env bash\necho "svc.sh $*" >>"%s"\n' "$PKG_LOG" >"$dir/svc.sh"
  chmod +x "$dir/svc.sh"
}

assert_remove_refused() { # msg-needle label: remove stopped before any effect
  local dir="$GITHUB_RUNNERS_DIR/$3"
  [[ "$RC" -ne 0 ]] && ok "$2: nonzero exit" || bad "$2: remove should fail"
  assert_contains "$OUT" "$1" "$2: explains the failure"
  assert_dir "$dir" "$2: folder kept"
  assert_not_contains "$(cat "$GH_LOG")" "api" "$2: no API call"
  assert_not_contains "$(cat "$PKG_LOG")" "svc.sh" "$2: service untouched"
  assert_not_contains "$(cat "$PKG_LOG")" "systemctl" "$2: systemd untouched"
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

# Build runner folders with logging svc.sh stubs, without going through add.
seed_runners() { # name...
  local n dir
  for n in "$@"; do
    dir="$GITHUB_RUNNERS_DIR/$n"
    mkdir -p "$dir"
    printf '#!/usr/bin/env bash\necho "%s svc.sh $*" >>"%s"\n' "$n" "$PKG_LOG" >"$dir/svc.sh"
    chmod +x "$dir/svc.sh"
  done
}

test_restart_glob_subset() {
  echo "test_restart_glob_subset"
  new_sandbox
  seed_runners actions-runner-acme-widget actions-runner-acme-gadget other-runner-acme
  run_runner restart 'actions-runner-acme-w*'
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "actions-runner-acme-widget svc.sh stop" "match stopped"
  assert_contains "$pkg" "actions-runner-acme-widget svc.sh start" "match started"
  assert_not_contains "$pkg" "actions-runner-acme-gadget" "non-match left alone"
  assert_not_contains "$pkg" "other-runner-acme" "prefix outside glob left alone"
  assert_contains "$OUT" "Restarted 1 runner" "reports how many"
  drop_sandbox
}

test_restart_glob_multiple() {
  echo "test_restart_glob_multiple"
  new_sandbox
  seed_runners actions-runner-acme-widget actions-runner-acme-gadget other-runner-acme
  run_runner restart '*acme*'
  assert_eq "$RC" "0" "exits 0"
  assert_contains "$OUT" "Restarted 3 runner" "all three matched"
  drop_sandbox
}

test_restart_glob_no_match_fails() {
  echo "test_restart_glob_no_match_fails"
  new_sandbox
  seed_runners actions-runner-acme-widget
  run_runner restart 'nothing-like-this-*'
  assert_eq "$RC" "1" "nonzero exit"
  assert_contains "$OUT" "no runner in" "explains the failure"
  drop_sandbox
}

test_restart_skips_folder_without_svc() {
  echo "test_restart_skips_folder_without_svc"
  new_sandbox
  mkdir -p "$GITHUB_RUNNERS_DIR/actions-runner-halfbuilt"
  run_runner restart 'actions-runner-halfbuilt'
  assert_eq "$RC" "1" "half-built folder is not a match"
  assert_contains "$OUT" "no runner in" "explains the failure"
  drop_sandbox
}

test_restart_requires_glob() {
  echo "test_restart_requires_glob"
  new_sandbox
  run_runner restart
  assert_eq "$RC" "1" "nonzero exit"
  assert_contains "$OUT" "usage:" "prints usage"
  drop_sandbox
}

test_restart_all_hits_every_runner() {
  echo "test_restart_all_hits_every_runner"
  new_sandbox
  seed_runners actions-runner-acme-widget actions-runner-acme-gadget
  run_runner restart-all
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "actions-runner-acme-widget svc.sh stop" "widget bounced"
  assert_contains "$pkg" "actions-runner-acme-gadget svc.sh stop" "gadget bounced"
  assert_contains "$OUT" "Runners restarted" "reports completion"
  drop_sandbox
}

test_add_asks_release_api_for_digest() {
  echo "test_add_asks_release_api_for_digest"
  new_sandbox
  run_runner add acme widget
  assert_eq "$RC" "0" "exits 0 on a matching digest"
  assert_contains "$(cat "$GH_LOG")" "api repos/actions/runner/releases/tags/v9.9.9" "reads the release of this version"
  drop_sandbox
}

test_add_seed_digest_mismatch() {
  echo "test_add_seed_digest_mismatch"
  new_sandbox
  echo "tampered" >"$RUNNER_TARBALL_SEED"
  run_runner add acme widget
  assert_add_refused "digest mismatch" "seed mismatch"
  drop_sandbox
}

test_add_cached_digest_mismatch() {
  echo "test_add_cached_digest_mismatch"
  new_sandbox
  run_runner add acme gadget
  assert_eq "$RC" "0" "first add caches a good tarball"
  echo "tampered" >"$GITHUB_RUNNERS_DIR/.cache/$TARBALL_NAME"
  : >"$PKG_LOG"; : >"$GH_LOG"
  run_runner add acme widget
  assert_add_refused "digest mismatch" "cached mismatch"
  drop_sandbox
}

test_add_download_digest_mismatch() {
  echo "test_add_download_digest_mismatch"
  new_sandbox
  unset RUNNER_TARBALL_SEED
  export DOWNLOAD_SRC="$WS/download.tgz"
  echo "tampered" >"$DOWNLOAD_SRC"
  run_runner add acme widget
  assert_add_refused "digest mismatch" "download mismatch"
  assert_contains "$(cat "$GH_LOG")" "release download" "the tarball came from a download"
  unset DOWNLOAD_SRC
  drop_sandbox
}

test_add_extracts_the_bytes_it_verified() {
  echo "test_add_extracts_the_bytes_it_verified"
  new_sandbox
  # A job swaps the cached tarball right after the hash.
  cat >"$WS/bin/sha256sum" <<'SHA'
#!/usr/bin/env bash
openssl dgst -sha256 -r "$1"
echo "tampered" >"$GITHUB_RUNNERS_DIR/.cache/$TARBALL_NAME"
SHA
  chmod +x "$WS/bin/sha256sum"
  mkdir "$WS/tmp"
  TMPDIR="$WS/tmp" run_runner add acme widget
  assert_eq "$RC" "0" "exits 0"
  assert_contains "$(cat "$PKG_LOG")" "tar-input dummy" "extracts the verified bytes"
  assert_eq "$(ls -A "$WS/tmp")" "" "leaves no private copy behind"
  drop_sandbox
}

test_add_refused_add_leaves_no_private_copy() {
  echo "test_add_refused_add_leaves_no_private_copy"
  new_sandbox
  echo "tampered" >"$RUNNER_TARBALL_SEED"
  mkdir "$WS/tmp"
  TMPDIR="$WS/tmp" run_runner add acme widget
  assert_add_refused "digest mismatch" "mismatch"
  assert_eq "$(ls -A "$WS/tmp")" "" "leaves no private copy behind"
  drop_sandbox
}

test_add_cached_entry_not_a_file() {
  echo "test_add_cached_entry_not_a_file"
  new_sandbox
  mkdir -p "$GITHUB_RUNNERS_DIR/.cache/$TARBALL_NAME"
  run_runner add acme widget
  assert_add_refused "no tarball at" "cached directory"
  drop_sandbox
}

test_add_missing_digest() {
  echo "test_add_missing_digest"
  new_sandbox
  write_release null
  run_runner add acme widget
  assert_add_refused "no digest" "null digest"
  drop_sandbox

  new_sandbox
  printf '{"assets":[]}\n' >"$RELEASE_JSON"
  run_runner add acme widget
  assert_add_refused "no digest" "asset absent"
  drop_sandbox

  new_sandbox
  rm "$RELEASE_JSON"
  run_runner add acme widget
  assert_add_refused "digest" "release API failure"
  drop_sandbox
}

test_add_linux_keeps_svc_install_under_sudo() {
  echo "test_add_linux_keeps_svc_install_under_sudo"
  new_sandbox
  linux_host
  run_runner add acme widget
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo ./svc.sh install" "install runs as root on the verified folder"
  assert_contains "$pkg" "sudo ./svc.sh start" "start runs as root on the verified folder"
  drop_sandbox
}

test_remove_rejects_bad_agent_id() {
  echo "test_remove_rejects_bad_agent_id"
  local bad_id folder="actions-runner-acme-widget"
  for bad_id in '"abc"' '"1/../2"' '"4 2"' '""' 'null' '-1'; do
    new_sandbox
    seed_configured_runner "$folder" "$bad_id" '"https://github.com/acme/widget"'
    run_runner remove "$folder"
    assert_remove_refused "agentId" "agentId $bad_id" "$folder"
    drop_sandbox
  done
}

test_remove_rejects_bad_github_url() {
  echo "test_remove_rejects_bad_github_url"
  local bad_url folder="actions-runner-acme-widget"
  for bad_url in \
    'http://github.com/acme' \
    'https://github.com.evil.example/acme' \
    'https://evil.example/https://github.com/acme' \
    'https://github.com/' \
    'https://github.com/acme/widget/extra' \
    'https://github.com/acme/..' \
    'https://github.com/acme/./' \
    'https://github.com/../user' \
    'https://github.com/acme/widget?x=1' \
    'https://github.com/acme/%2e%2e' \
    'https://github.com/acme//widget'; do
    new_sandbox
    seed_configured_runner "$folder" 42 "\"$bad_url\""
    run_runner remove "$folder"
    assert_remove_refused "gitHubUrl" "url $bad_url" "$folder"
    drop_sandbox
  done
}

test_remove_accepts_github_name_characters() {
  echo "test_remove_accepts_github_name_characters"
  local good folder="actions-runner-acme-widget"
  for good in \
    'https://github.com/acme|/orgs/acme/' \
    'https://github.com/acme/|/orgs/acme/' \
    'https://github.com/Acme-1/.github|/repos/Acme-1/.github/' \
    'https://github.com/acme/my_repo.v2-x/|/repos/acme/my_repo.v2-x/'; do
    new_sandbox
    seed_configured_runner "$folder" 42 "\"${good%%|*}\""
    run_runner remove "$folder"
    assert_eq "$RC" "0" "${good%%|*}: exits 0"
    assert_contains "$(cat "$GH_LOG")" "api -X DELETE ${good##*|}actions/runners/42" "${good%%|*}: deregisters"
    assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "${good%%|*}: folder deleted"
    drop_sandbox
  done
}

test_remove_linux_uses_systemctl() {
  echo "test_remove_linux_uses_systemctl"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget" unit="actions.runner.acme-widget.actions-runner-acme-widget.service"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  echo "$unit" >"$GITHUB_RUNNERS_DIR/$folder/.service"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo systemctl stop $unit" "stops the unit"
  assert_contains "$pkg" "sudo systemctl disable $unit" "disables the unit"
  assert_contains "$pkg" "sudo rm -f /etc/systemd/system/$unit" "deletes the unit file"
  assert_contains "$pkg" "sudo systemctl daemon-reload" "reloads systemd"
  assert_not_contains "$pkg" "svc.sh" "never runs svc.sh"
  assert_contains "$(cat "$GH_LOG")" "api -X DELETE /repos/acme/widget/actions/runners/42" "deregisters"
  assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "folder deleted"
  drop_sandbox
}

test_remove_linux_rejects_bad_unit() {
  echo "test_remove_linux_rejects_bad_unit"
  local bad_unit folder="actions-runner-acme-widget"
  for bad_unit in \
    'sshd.service' \
    'actions.runner.a/../../sshd.service' \
    'actions.runner.*.service' \
    'actions.runner.a b.service' \
    'actions.runner.service' \
    $'actions.runner.a.service\nactions.runner.b.service' \
    'actions.runner.a.service ' \
    '../actions.runner.a.service'; do
    new_sandbox
    linux_host
    seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
    echo "$bad_unit" >"$GITHUB_RUNNERS_DIR/$folder/.service"
    run_runner remove "$folder"
    assert_remove_refused ".service" "unit $bad_unit" "$folder"
    assert_not_contains "$(cat "$PKG_LOG")" "sudo" "unit $bad_unit: nothing ran as root"
    drop_sandbox
  done
}

test_remove_linux_without_service_file() {
  echo "test_remove_linux_without_service_file"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  assert_contains "$OUT" "list-unit-files" "says how to find a leftover unit"
  assert_contains "$OUT" "sudo rm /etc/systemd/system/" "says how to clear a leftover unit"
  assert_not_contains "$(cat "$PKG_LOG")" "sudo" "nothing ran as root"
  assert_contains "$(cat "$GH_LOG")" "api -X DELETE /repos/acme/widget/actions/runners/42" "still deregisters"
  assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "folder deleted"
  drop_sandbox
}

test_remove_linux_finds_the_unit_a_job_hid() {
  echo "test_remove_linux_finds_the_unit_a_job_hid"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  export STUB_UNIT="actions.runner.acme-widget.a.service" STUB_UNIT_DIR="$GITHUB_RUNNERS_DIR/$folder"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo systemctl stop $STUB_UNIT" "stops the unit"
  assert_contains "$pkg" "sudo systemctl disable $STUB_UNIT" "disables the unit"
  assert_contains "$pkg" "sudo rm -f /etc/systemd/system/$STUB_UNIT" "deletes the unit file"
  assert_contains "$pkg" "sudo systemctl daemon-reload" "reloads systemd"
  assert_not_contains "$OUT" "warning" "nothing is left to warn about"
  assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "folder deleted"
  drop_sandbox
}

test_remove_linux_installed_unit_beats_service_file() {
  echo "test_remove_linux_installed_unit_beats_service_file"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  echo "actions.runner.acme-other.b.service" >"$GITHUB_RUNNERS_DIR/$folder/.service"
  export STUB_UNIT="actions.runner.acme-widget.a.service" STUB_UNIT_DIR="$GITHUB_RUNNERS_DIR/$folder"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo rm -f /etc/systemd/system/$STUB_UNIT" "removes this runner's unit"
  assert_not_contains "$pkg" "actions.runner.acme-other" "another runner's unit is safe"
  drop_sandbox
}

test_remove_linux_ignores_another_folders_unit() {
  echo "test_remove_linux_ignores_another_folders_unit"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  export STUB_UNIT="actions.runner.acme-other.b.service" STUB_UNIT_DIR="$GITHUB_RUNNERS_DIR/actions-runner-acme-other"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  assert_not_contains "$(cat "$PKG_LOG")" "sudo" "another runner's unit is safe"
  drop_sandbox
}

test_remove_linux_half_built_removes_the_unit() {
  echo "test_remove_linux_half_built_removes_the_unit"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget" unit="actions.runner.acme-widget.a.service"
  mkdir -p "$GITHUB_RUNNERS_DIR/$folder"
  echo "$unit" >"$GITHUB_RUNNERS_DIR/$folder/.service"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo systemctl stop $unit" "stops the unit"
  assert_contains "$pkg" "sudo rm -f /etc/systemd/system/$unit" "deletes the unit file"
  assert_not_contains "$OUT" "Deleting folder only" "reports what ran as root"
  assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "folder deleted"
  drop_sandbox
}

test_remove_linux_half_built_rejects_bad_unit() {
  echo "test_remove_linux_half_built_rejects_bad_unit"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  mkdir -p "$GITHUB_RUNNERS_DIR/$folder"
  echo "sshd.service" >"$GITHUB_RUNNERS_DIR/$folder/.service"
  run_runner remove "$folder"
  assert_remove_refused ".service" "half-built bad unit" "$folder"
  assert_contains "$OUT" "Delete that file" "says how to clear the folder"
  assert_not_contains "$(cat "$PKG_LOG")" "sudo" "nothing ran as root"
  drop_sandbox
}

test_remove_linux_half_built_without_service_file() {
  echo "test_remove_linux_half_built_without_service_file"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  mkdir -p "$GITHUB_RUNNERS_DIR/$folder"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0"
  assert_contains "$OUT" "list-unit-files" "says how to find a leftover unit"
  assert_not_contains "$(cat "$PKG_LOG")" "sudo" "nothing ran as root"
  assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "folder deleted"
  drop_sandbox
}

test_remove_linux_tolerates_stop_and_disable_failures() {
  echo "test_remove_linux_tolerates_stop_and_disable_failures"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  echo "actions.runner.acme-widget.a.service" >"$GITHUB_RUNNERS_DIR/$folder/.service"
  printf '#!/usr/bin/env bash\n[[ "$1" == "daemon-reload" ]]\n' >"$WS/bin/systemctl"
  run_runner remove "$folder"
  assert_eq "$RC" "0" "exits 0: the service was not installed"
  assert_contains "$(cat "$GH_LOG")" "api -X DELETE" "deregisters"
  assert_nodir "$GITHUB_RUNNERS_DIR/$folder" "folder deleted"
  drop_sandbox
}

test_remove_linux_keeps_folder_when_unit_file_stays() {
  echo "test_remove_linux_keeps_folder_when_unit_file_stays"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget" unit="actions.runner.acme-widget.a.service"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  echo "$unit" >"$GITHUB_RUNNERS_DIR/$folder/.service"
  printf '#!/usr/bin/env bash\n[[ "$1" == "rm" ]] && exit 1\nexec "$@"\n' >"$WS/bin/sudo"
  run_runner remove "$folder"
  [[ "$RC" -ne 0 ]] && ok "nonzero exit" || bad "should fail when the unit file stays"
  assert_contains "$OUT" "$unit" "names the unit"
  assert_dir "$GITHUB_RUNNERS_DIR/$folder" "folder keeps the only record of the unit name"
  assert_not_contains "$(cat "$GH_LOG")" "DELETE" "runner stays registered"
  drop_sandbox
}

test_restart_linux_uses_systemctl() {
  echo "test_restart_linux_uses_systemctl"
  new_sandbox
  linux_host
  seed_runners actions-runner-acme-widget actions-runner-acme-gadget
  echo "actions.runner.acme-widget.w.service" >"$GITHUB_RUNNERS_DIR/actions-runner-acme-widget/.service"
  run_runner restart 'actions-runner-acme-w*'
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo systemctl restart actions.runner.acme-widget.w.service" "restarts the unit"
  assert_not_contains "$pkg" "svc.sh" "never runs svc.sh"
  assert_contains "$OUT" "Restarted 1 runner" "reports how many"
  drop_sandbox
}

test_restart_linux_rejects_bad_unit() {
  echo "test_restart_linux_rejects_bad_unit"
  new_sandbox
  linux_host
  seed_runners actions-runner-acme-widget actions-runner-acme-gadget actions-runner-acme-unset
  echo "sshd.service" >"$GITHUB_RUNNERS_DIR/actions-runner-acme-widget/.service"
  echo "actions.runner.acme-gadget.g.service" >"$GITHUB_RUNNERS_DIR/actions-runner-acme-gadget/.service"
  run_runner restart 'actions-runner-acme-*'
  assert_eq "$RC" "0" "exits 0: the good runner restarted"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo systemctl restart actions.runner.acme-gadget.g.service" "good unit restarted"
  assert_not_contains "$pkg" "sshd.service" "bad unit never reaches systemctl"
  assert_not_contains "$pkg" "svc.sh" "never runs svc.sh"
  assert_contains "$OUT" "warning: no valid unit for actions-runner-acme-widget" "warns on the bad unit"
  assert_contains "$OUT" "warning: no valid unit for actions-runner-acme-unset" "warns on no unit"
  assert_contains "$OUT" "Restarted 1 runner" "counts only the runner it restarted"
  drop_sandbox
}

test_restart_linux_only_bad_unit_fails() {
  echo "test_restart_linux_only_bad_unit_fails"
  new_sandbox
  linux_host
  seed_runners actions-runner-acme-widget
  echo "actions.runner.*.service" >"$GITHUB_RUNNERS_DIR/actions-runner-acme-widget/.service"
  run_runner restart 'actions-runner-acme-widget'
  [[ "$RC" -ne 0 ]] && ok "nonzero exit" || bad "should fail with nothing restarted"
  assert_contains "$OUT" "no valid unit in any runner" "says why, not that nothing matched"
  assert_not_contains "$OUT" "no runner in" "the glob did match"
  assert_not_contains "$(cat "$PKG_LOG")" "sudo" "nothing ran as root"
  drop_sandbox
}

test_restart_linux_needs_no_svc_sh() {
  echo "test_restart_linux_needs_no_svc_sh"
  new_sandbox
  linux_host
  seed_runners actions-runner-acme-widget
  echo "actions.runner.acme-widget.w.service" >"$GITHUB_RUNNERS_DIR/actions-runner-acme-widget/.service"
  rm "$GITHUB_RUNNERS_DIR/actions-runner-acme-widget/svc.sh"
  run_runner restart 'actions-runner-acme-widget'
  assert_eq "$RC" "0" "exits 0"
  assert_contains "$(cat "$PKG_LOG")" "sudo systemctl restart actions.runner.acme-widget.w.service" "restarts the unit"
  drop_sandbox
}

test_restart_linux_warns_on_configured_folder_without_service_files() {
  echo "test_restart_linux_warns_on_configured_folder_without_service_files"
  new_sandbox
  linux_host
  local folder="actions-runner-acme-widget"
  seed_configured_runner "$folder" 42 '"https://github.com/acme/widget"'
  rm "$GITHUB_RUNNERS_DIR/$folder/svc.sh"
  run_runner restart "$folder"
  [[ "$RC" -ne 0 ]] && ok "nonzero exit" || bad "should fail with nothing restarted"
  assert_contains "$OUT" "warning: no valid unit for $folder" "warns instead of skipping silently"
  drop_sandbox
}

test_restart_linux_skips_folder_that_is_no_runner() {
  echo "test_restart_linux_skips_folder_that_is_no_runner"
  new_sandbox
  linux_host
  seed_runners actions-runner-acme-widget
  echo "actions.runner.acme-widget.w.service" >"$GITHUB_RUNNERS_DIR/actions-runner-acme-widget/.service"
  mkdir -p "$GITHUB_RUNNERS_DIR/.cache"
  run_runner restart '*'
  assert_eq "$RC" "0" "exits 0"
  assert_not_contains "$OUT" "warning" "the cache is not a runner"
  drop_sandbox
}

test_restart_all_linux_uses_systemd_glob() {
  echo "test_restart_all_linux_uses_systemd_glob"
  new_sandbox
  linux_host
  seed_runners actions-runner-acme-widget
  run_runner restart-all
  assert_eq "$RC" "0" "exits 0"
  local pkg; pkg="$(cat "$PKG_LOG")"
  assert_contains "$pkg" "sudo systemctl restart actions.runner.*" "systemd glob used"
  assert_not_contains "$pkg" "svc.sh" "never runs svc.sh"
  drop_sandbox
}

test_add_repo
test_add_org
test_add_user_no_repo_fails
test_add_collision_suffix
test_add_asks_release_api_for_digest
test_add_seed_digest_mismatch
test_add_cached_digest_mismatch
test_add_download_digest_mismatch
test_add_extracts_the_bytes_it_verified
test_add_refused_add_leaves_no_private_copy
test_add_cached_entry_not_a_file
test_add_missing_digest
test_add_linux_keeps_svc_install_under_sudo
test_remove_repo
test_remove_half_built
test_remove_rejects_bad_agent_id
test_remove_rejects_bad_github_url
test_remove_accepts_github_name_characters
test_remove_linux_uses_systemctl
test_remove_linux_rejects_bad_unit
test_remove_linux_without_service_file
test_remove_linux_finds_the_unit_a_job_hid
test_remove_linux_installed_unit_beats_service_file
test_remove_linux_ignores_another_folders_unit
test_remove_linux_half_built_removes_the_unit
test_remove_linux_half_built_rejects_bad_unit
test_remove_linux_half_built_without_service_file
test_remove_linux_tolerates_stop_and_disable_failures
test_remove_linux_keeps_folder_when_unit_file_stays
test_restart_linux_uses_systemctl
test_restart_linux_rejects_bad_unit
test_restart_linux_only_bad_unit_fails
test_restart_linux_needs_no_svc_sh
test_restart_linux_warns_on_configured_folder_without_service_files
test_restart_linux_skips_folder_that_is_no_runner
test_restart_all_linux_uses_systemd_glob
test_list_org
test_list_repo
test_list_user_no_repo_fails
test_api_target_from_url
test_restart_glob_subset
test_restart_glob_multiple
test_restart_glob_no_match_fails
test_restart_skips_folder_without_svc
test_restart_requires_glob
test_restart_all_hits_every_runner

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
