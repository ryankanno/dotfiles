#!/usr/bin/env bash
# Tests for the interactive shell helpers: the address pyserver serves on,
# and the nvim command line the fzf key binds build. PATH stubs stand in for
# python, the browser openers, fzf, and nvim, so no server starts, no
# browser opens, and no editor runs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0
WS=""
SANDBOXES=()

# A recorder stub writes its argv, one [arg] per argument, to $WS/<name>.argv.
new_sandbox() {
  WS="$(mktemp -d "${TMPDIR:-/tmp}/shell-helpers-test.XXXXXXXX")"; SANDBOXES+=("$WS")
  mkdir "$WS/bin"
  local name
  for name in python open xdg-open nvim; do
    cat >"$WS/bin/$name" <<'STUB'
#!/usr/bin/env bash
printf '[%s]' "$@" >"$STUB_DIR/${0##*/}.argv"
STUB
  done
  # dot_fzf.bash evals `fzf --bash`; the stub prints no key bindings for it.
  cat >"$WS/bin/fzf" <<'STUB'
#!/usr/bin/env bash
[[ ${1-} == --bash ]] || printf '%s\n' "$FZF_PICK"
STUB
  chmod +x "$WS/bin/"*
  export STUB_DIR="$WS"
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

# --- pyserver ---

new_sandbox
PATH="$WS/bin:$PATH" bash -c 'source "$1"; pyserver' _ "$ROOT/dot_bash_functions" >/dev/null 2>&1
assert_contains "$(cat "$WS/python.argv" 2>/dev/null)" "[--bind][127.0.0.1]" \
  "pyserver binds http.server to loopback"

# --- fzf key binds ---

# dot_fzf.bash binds keys only when stdout is a terminal, so it is sourced
# under script(1)'s pty. Prints the command bound to key sequence $1.
# shortcut: BSD script(1) syntax only, add util-linux's `script -qec` form when this suite runs on Linux.
bound_command() {
  local line
  PATH="$WS/bin:$PATH" script -q /dev/null \
    bash -c 'source "$1"; bind -X >"$2" 2>/dev/null' _ "$ROOT/dot_fzf.bash" "$WS/binds" \
    </dev/null >/dev/null 2>&1
  # bind -X prints each bind as: "<keyseq>" "<command with \" escapes>"
  while IFS= read -r line; do
    [[ $line == "\"$1\" \""*\" ]] || continue
    line="${line#"\"$1\" \""}"; line="${line%\"}"
    printf '%s\n' "${line//\\\"/\"}"
  done <"$WS/binds"
}

# Runs the command bound to $1 with fzf selecting $2; sets ARGV to nvim's argv.
run_bind() {
  local cmd
  cmd="$(bound_command "$1")"
  rm -f "$WS/nvim.argv"
  FZF_PICK="$2" PATH="$WS/bin:$PATH" bash -c 'source "$1"; eval "$2"' _ "$ROOT/dot_fzf.bash" "$cmd" \
    >/dev/null 2>&1
  ARGV="$(cat "$WS/nvim.argv" 2>/dev/null)"
}

new_sandbox
for key in '\C-p' '\C-f'; do
  run_bind "$key" '-S evil.vim'
  assert_eq "$ARGV" "[--][-S evil.vim]" "$key bind passes a dash-led selection to nvim as one file name"
  run_bind "$key" '-S'
  assert_eq "$ARGV" "[--][-S]" "$key bind passes a bare -S to nvim as a file name"
done

report
