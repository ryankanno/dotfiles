#!/usr/bin/env bash
# Tests for the ntfy subscriber configs: the real chezmoi runs on this checkout
# with a sandboxed config, destination, and HOME. --override-data sets
# .chezmoi.os, so both platforms' configs run on either host.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0
WS=""
SANDBOXES=()
PROMPT='ntfy server URL, https:// (empty skips the ntfy configs)'

# The applying shell's value is the thing under test, so no case inherits it.
unset NTFY_SERVER_URL

new_sandbox() {
  WS="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-templates-test.XXXXXXXX")"; SANDBOXES+=("$WS")
  mkdir "$WS/home" "$WS/config"
}
trap '[[ ${#SANDBOXES[@]} -eq 0 ]] || rm -rf "${SANDBOXES[@]}"' EXIT
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

cm() {
  HOME="$WS/home" chezmoi --no-tty --source "$ROOT" --config "$WS/config/chezmoi.toml" \
    --destination "$WS/home" --override-data "{\"chezmoi\":{\"os\":\"$OS\"}}" "$@"
}

# $1 is a TOML basic string body, so its escapes reach chezmoi as real bytes.
set_host() {
  printf '[data.ntfy]\n    host = "%s"\n' "$1" >"$WS/config/chezmoi.toml"
}

# Sets ERR from the apply of one target, and RC to its exit code.
apply_target() {
  mkdir -p "$WS/home/$(dirname "$TARGET")"
  cm apply "$WS/home/$TARGET" >/dev/null 2>"$WS/err"
  RC=$?
  ERR="$(cat "$WS/err")"
}

# Asserts that the current sandbox skips both configs and that the apply succeeds.
assert_skipped() {
  local managed
  managed="$(cm managed 2>"$WS/err")"
  assert_eq "$?" 0 "$1: chezmoi managed succeeds"$'\n'"$(cat "$WS/err")"
  assert_eq "$(grep -cE '^\.config/ntfy(-macos)?(/|$)' <<<"$managed")" 0 "$1: chezmoi managed lists no ntfy config"
  cm apply >/dev/null 2>"$WS/err"
  assert_eq "$?" 0 "$1: the apply succeeds"$'\n'"$(cat "$WS/err")"
  assert_eq "$(ls "$WS/home/.config/ntfy" "$WS/home/.config/ntfy-macos" 2>/dev/null)" "" \
    "$1: the apply writes no ntfy config"
}

for OS in linux darwin; do
  if [[ $OS == linux ]]; then
    TARGET=.config/ntfy/client.yml OTHER=.config/ntfy-macos KEY='default-host: '
  else
    TARGET=.config/ntfy-macos/config.yml OTHER=.config/ntfy KEY='  - url: '
  fi
  LINE="$KEY\"https://ntfy.example/base\""

  # --- a valid host ---

  new_sandbox
  set_host 'https://ntfy.example/base'
  assert_contains "$(cm managed 2>/dev/null)" "$TARGET" "$OS: chezmoi managed lists the config"
  assert_eq "$(cm managed 2>/dev/null | grep -cE "^$OTHER(/|$)")" 0 "$OS: chezmoi managed leaves out the other platform's config"
  cm apply >/dev/null 2>"$WS/err"
  assert_eq "$?" 0 "$OS: the apply of a valid host succeeds"$'\n'"$(cat "$WS/err")"
  assert_eq "$(grep -cxF -- "$LINE" "$WS/home/$TARGET" 2>/dev/null)" 1 "$OS: the host renders on its line"

  # The control that lets the failing single-target applies below mean something.
  new_sandbox
  set_host 'https://ntfy.example/base'
  apply_target
  assert_eq "$RC" 0 "$OS: a single-target apply of a valid host succeeds"$'\n'"$ERR"
  assert_eq "$(grep -cxF -- "$LINE" "$WS/home/$TARGET" 2>/dev/null)" 1 "$OS: a single-target apply writes the config"

  # A trailing colon is a YAML mapping indicator unless the value is quoted.
  new_sandbox
  set_host 'https://ntfy.example:'
  apply_target
  assert_eq "$(grep -cxF -- "$KEY\"https://ntfy.example:\"" "$WS/home/$TARGET" 2>/dev/null)" 1 \
    "$OS: a host ending in a colon renders as a quoted scalar"

  # --- a host that is not a single-line https:// URL ---

  for host in \
    'https://ntfy.example\nsubscribe:\n  - topic: x\n    command: evil' \
    'https://ntfy.example\n' \
    '\nhttps://ntfy.example' \
    'https://ntfy.example\rcommand: evil' \
    'http://ntfy.example' \
    'file:///etc/passwd' \
    'ntfy.example' \
    'https://' \
    'https://ntfy example' \
    'https://ntfy.example\u0001' \
    'https://ntfy.example\u007f' \
    'https://ntfy.example\u0085' \
    'https://ntfy.example '; do
    new_sandbox
    set_host "$host"
    apply_target
    assert_eq "$([[ $RC -ne 0 ]] && echo failed)" failed "$OS: the apply fails for $host"
    assert_contains "$ERR" ntfy.host "$OS: the failure for $host names ntfy.host"
    assert_eq "$(ls "$WS/home/$TARGET" 2>/dev/null)" "" "$OS: no config is written for $host"
  done

  new_sandbox
  printf '[data.ntfy]\n    host = 5\n' >"$WS/config/chezmoi.toml"
  apply_target
  assert_eq "$([[ $RC -ne 0 ]] && echo failed)" failed "$OS: the apply fails for a host that is not a string"
  assert_contains "$ERR" ntfy.host "$OS: the failure for a host that is not a string names ntfy.host"

  # --- an empty or missing host ---

  new_sandbox
  set_host ''
  assert_skipped "$OS: empty host"

  new_sandbox
  printf '[data.ntfy]\n' >"$WS/config/chezmoi.toml"
  assert_skipped "$OS: ntfy table with no host"

  new_sandbox
  : >"$WS/config/chezmoi.toml"
  assert_skipped "$OS: no ntfy data"

  # --- NTFY_SERVER_URL in the environment ---

  new_sandbox
  set_host 'https://ntfy.example/base'
  export NTFY_SERVER_URL=$'https://evil.example\nsubscribe:\n  - topic: x\n    command: evil'
  cm apply >/dev/null 2>"$WS/err"
  assert_eq "$?" 0 "$OS: the environment does not fail the apply"$'\n'"$(cat "$WS/err")"
  assert_eq "$(grep -cxF -- "$LINE" "$WS/home/$TARGET" 2>/dev/null)" 1 "$OS: ntfy.host wins over the environment"
  assert_eq "$(grep -c evil "$WS/home/$TARGET" 2>/dev/null)" 0 "$OS: the environment value reaches no config"

  new_sandbox
  : >"$WS/config/chezmoi.toml"
  assert_skipped "$OS: the environment does not stand in for a missing host"
  unset NTFY_SERVER_URL

  # --- chezmoi init ---

  new_sandbox
  cm init --promptString "$PROMPT=https://first.example" >/dev/null 2>"$WS/err"
  assert_eq "$?" 0 "$OS: init succeeds"$'\n'"$(cat "$WS/err")"
  assert_eq "$(cm execute-template '{{ .ntfy.host }}' 2>/dev/null)" https://first.example \
    "$OS: init stores the answer as ntfy.host"
  assert_eq "$(cm execute-template '{{ .chezmoi.config.diff.pager }}' 2>/dev/null)" delta \
    "$OS: init keeps the diff pager"
  cm init --promptString "$PROMPT=https://second.example" >/dev/null 2>&1
  assert_eq "$(cm execute-template '{{ .ntfy.host }}' 2>/dev/null)" https://first.example \
    "$OS: a second init does not ask again"

  new_sandbox
  cm init --promptString "$PROMPT=" >/dev/null 2>&1
  assert_skipped "$OS: an empty answer at init"
done

report
