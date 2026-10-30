#!/usr/bin/env bash
# Tests for the interactive shell helpers: the address pyserver serves on,
# the nvim command line the fzf key binds build, and the direnv use_venv and
# use_uv functions. PATH stubs stand in for python, the browser openers, fzf,
# nvim, and uv, so no server starts, no browser opens, no editor runs, and no
# virtualenv is built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0
WS=""
SANDBOXES=()

# A recorder stub writes its argv, one [arg] per argument, to $WS/<name>.argv.
# python3 is stubbed too, so a pyserver that runs python3 fails the test
# instead of starting a real server that hangs it.
new_sandbox() {
  WS="$(mktemp -d "${TMPDIR:-/tmp}/shell-helpers-test.XXXXXXXX")"; SANDBOXES+=("$WS")
  mkdir "$WS/bin"
  local name
  for name in python python3 open xdg-open nvim; do
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
PATH="$WS/bin:$PATH" bash -c 'source "$1"; pyserver 9000' _ "$ROOT/dot_bash_functions" >/dev/null 2>&1
assert_eq "$(cat "$WS/python.argv" 2>/dev/null)" "[-m][http.server][--bind][127.0.0.1][9000]" \
  "pyserver serves the requested port on loopback"

# --- tm and tmk ---

# The tmux stub appends each call's argv as one line to $WS/tmux.calls, lists
# frompineapples.com, and fails any target not in $TMUX_TARGETS.
new_sandbox
cat >"$WS/bin/tmux" <<'STUB'
#!/usr/bin/env bash
printf '[%s]' "$@" >>"$STUB_DIR/tmux.calls"; echo >>"$STUB_DIR/tmux.calls"
[[ $1 == list-sessions ]] && { echo frompineapples.com; exit 0; }
[[ " ${TMUX_TARGETS-} " == *" $3 "* ]] || { echo "can't find session: $3" >&2; exit 1; }
STUB
chmod +x "$WS/bin/tmux"

# Runs $1 with fzf picking $2 and tmux accepting targets $3; sets LAST, CALLS and ERR.
run_tmux_fn() {
  rm -f "$WS/tmux.calls"
  FZF_PICK="$2" TMUX_TARGETS="$3" PATH="$WS/bin:$PATH" \
    bash -c 'source "$1"; eval "$2"' _ "$ROOT/dot_bash_functions" "$1" >/dev/null 2>"$WS/tmux.err" </dev/null
  CALLS="$(cat "$WS/tmux.calls" 2>/dev/null)"
  LAST="$(tail -n 1 <<<"$CALLS")"
  ERR="$(cat "$WS/tmux.err")"
}

run_tmux_fn 'TMUX=1 tm frompineapples.com' frompineapples.com '=frompineapples.com:'
assert_eq "$LAST" "[switch-client][-t][=frompineapples.com:]" \
  "tm inside tmux switches to a dotted session by its exact name"
run_tmux_fn 'unset TMUX; tm frompineapples.com' frompineapples.com '=frompineapples.com:'
assert_eq "$LAST" "[attach-session][-t][=frompineapples.com:]" \
  "tm outside tmux attaches to a dotted session by its exact name"
# list-sessions prints a name made with `new-session -s 'a\b'` as a\\b, so that is the name tm and tmk get.
bs='a\\b'
run_tmux_fn 'TMUX=1 tm' "$bs" "=$bs:"
assert_eq "$LAST" "[switch-client][-t][=$bs:]" \
  "tm switches to a session with a backslash in its name by its exact name"
run_tmux_fn "tmk $(printf %q "$bs")" '' "=$bs:"
assert_eq "$CALLS" "[kill-session][-t][=$bs:]" \
  "tmk kills a session with a backslash in its name by its exact name"
run_tmux_fn 'tmk frompineapples.com' '' '=frompineapples.com:'
assert_eq "$CALLS" "[kill-session][-t][=frompineapples.com:]" \
  "tmk kills a dotted session by its exact name"
run_tmux_fn 'tmk fromp' '' 'fromp'
assert_eq "$LAST" "[kill-session][-t][fromp]" \
  "tmk falls back to the tmux prefix match when no session has the exact name"
run_tmux_fn 'tmk nosuch' '' ''
assert_contains "$ERR" "can't find session: nosuch" \
  "tmk reports tmux's error when no session matches"
# tmux reads a plain "x.1" as session or window x, pane 1, and kills the session that holds it.
run_tmux_fn 'tmk x.1' '' ''
assert_eq "$CALLS" "[kill-session][-t][=x.1:]" \
  "tmk does not fall back to a plain target for a dotted name with no exact match"
assert_contains "$ERR" "can't find session: =x.1:" \
  "tmk reports tmux's error for a dotted name with no exact match"

# --- fzf key binds ---

# dot_fzf.bash binds keys only when stdout is a terminal, so it is sourced
# under script(1)'s pty. Prints the command bound to key sequence $1.
# shortcut: BSD script(1) syntax only, add util-linux's `script -qec` form when this suite runs on Linux.
bound_command() {
  local line rest
  PATH="$WS/bin:$PATH" script -q /dev/null \
    bash -c 'source "$1"; bind -X >"$2" 2>/dev/null' _ "$ROOT/dot_fzf.bash" "$WS/binds" \
    </dev/null >/dev/null 2>&1
  # bind -X prints each bind as "<keyseq>" "<command>" (bash 5.3) or
  # "<keyseq>": "<command>" (bash 5.2), with \" escapes in the command.
  while IFS= read -r line; do
    rest="${line#"\"$1\""}"; rest="${rest#:}"
    [[ $rest != "$line" && $rest == ' "'*\" ]] || continue
    rest="${rest#' "'}"; rest="${rest%\"}"
    printf '%s\n' "${rest//\\\"/\"}"
  done <"$WS/binds"
}

# Runs command $1 with fzf selecting $2; sets ARGV to nvim's argv.
run_bind() {
  rm -f "$WS/nvim.argv"
  FZF_PICK="$2" PATH="$WS/bin:$PATH" bash -c 'source "$1"; eval "$2"' _ "$ROOT/dot_fzf.bash" "$1" \
    >/dev/null 2>&1
  ARGV="$(cat "$WS/nvim.argv" 2>/dev/null)"
}

new_sandbox
for key in '\C-p' '\C-f'; do
  cmd="$(bound_command "$key")"
  assert_contains "$cmd" "nvim" "bind -X lists the $key bind (it needs bash 4 or later and BSD script(1))"
  run_bind "$cmd" '-S evil.vim'
  assert_eq "$ARGV" "[--][-S evil.vim]" "$key bind passes a dash-led selection to nvim as one file name"
  run_bind "$cmd" '-S'
  assert_eq "$ARGV" "[--][-S]" "$key bind passes a bare -S to nvim as a file name"
done

# --- dot_bashrc PATH ---

# The npm stub reports the prefix in the start directory's .npmrc. npm 11
# refuses that prefix, so a real npm cannot show a shell that trusts the
# report. A bare PATH keeps the real mise and direnv out of the shell start,
# and its repeated entry proves the rc file ran: the rc file's dedup removes it.
new_sandbox
cat >"$WS/bin/npm" <<'STUB'
#!/usr/bin/env bash
[[ $* == 'config get prefix' ]] && sed -n 's/^prefix=//p' .npmrc
STUB
chmod +x "$WS/bin/npm"
mkdir "$WS/home" "$WS/repo"
echo "prefix=$WS/evil" >"$WS/repo/.npmrc"
(cd "$WS/repo" && HOME="$WS/home" PATH="$WS/bin:/usr/bin:$WS/bin:/bin" script -q /dev/null \
  "$BASH" --noprofile --rcfile "$ROOT/dot_bashrc" -ic 'printf %s "$PATH" >"$1"' _ "$WS/path" \
  </dev/null >/dev/null 2>&1)
assert_eq "$(cat "$WS/path" 2>/dev/null)" "$WS/bin:/usr/bin:/bin" \
  "a start directory's .npmrc prefix does not reach PATH"

# --- direnv use_venv and use_uv ---

# The real direnv loads this direnvrc from a sandboxed config directory, with
# the allow list in a sandboxed data directory. The uv stub appends each call's
# argv to $WS/uv.calls and, for `uv venv`, keeps or creates .venv/bin as
# --allow-existing does. $UV_VENV_FAIL makes `uv venv` fail.
new_direnv_sandbox() {
  new_sandbox
  mkdir -p "$WS/config/direnv" "$WS/data" "$WS/cache" "$WS/home" "$WS/repo"
  # direnv reports the physical path, and macOS's temp directory is a symlink.
  REPO="$(cd "$WS/repo" && pwd -P)"
  cp "$ROOT/dot_config/direnv/direnvrc" "$WS/config/direnv/direnvrc"
  cat >"$WS/bin/uv" <<'STUB'
#!/usr/bin/env bash
printf '[%s]' "$@" >>"$STUB_DIR/uv.calls"; echo >>"$STUB_DIR/uv.calls"
[[ $1 == venv ]] || exit 0
[[ -z ${UV_VENV_FAIL-} ]] || exit 1
mkdir -p .venv/bin
STUB
  chmod +x "$WS/bin/uv"
}

# Runs $@ in $WS/repo with the sandbox's direnv state and none of the caller's.
in_direnv_repo() {
  (cd "$WS/repo" && env -u DIRENV_DIFF -u DIRENV_DIR -u DIRENV_FILE -u DIRENV_WATCHES -u VIRTUAL_ENV \
    HOME="$WS/home" XDG_CONFIG_HOME="$WS/config" XDG_DATA_HOME="$WS/data" XDG_CACHE_HOME="$WS/cache" \
    PATH="$WS/bin:$PATH" "$@")
}

# Writes $1 as the repository's .envrc and allows it.
allow_envrc() {
  echo "$1" >"$WS/repo/.envrc"
  in_direnv_repo direnv allow . >/dev/null 2>&1
}

# Evaluates what the shell hook evaluates at a prompt in $WS/repo, with
# PYTHONHOME set as a shell could have it. Sets VENV, PYHOME, FIRST_PATH, ERR
# and UV_CALLS.
direnv_prompt() {
  rm -f "$WS/env"
  in_direnv_repo env PYTHONHOME=/from/the/shell bash -c \
    'eval "$(direnv export bash)"; printf "%s\n" "${VIRTUAL_ENV-}" "${PYTHONHOME-unset}" "$PATH" >"$STUB_DIR/env"' \
    >/dev/null 2>"$WS/direnv.err"
  { IFS= read -r VENV; IFS= read -r PYHOME; IFS= read -r FIRST_PATH; } <"$WS/env"
  FIRST_PATH="${FIRST_PATH%%:*}"
  ERR="$(cat "$WS/direnv.err")"
  UV_CALLS="$(cat "$WS/uv.calls" 2>/dev/null)"
}

git_commit_all() {
  in_direnv_repo git init -q
  in_direnv_repo git add -A
  in_direnv_repo git -c user.name=test -c user.email=test@example.com commit -qm test
}

# Each marker file a repository script leaves proves the script ran.
ran() { if [[ -e "$WS/$1.ran" ]]; then echo yes; else echo no; fi; }
write_marker_script() {
  mkdir -p "$(dirname "$1")"
  echo ": >\"\$STUB_DIR/$2.ran\"" >"$1"
}

new_direnv_sandbox
allow_envrc 'use uv'
write_marker_script "$WS/repo/.envrc.local" sidecar
direnv_prompt
assert_eq "$(ran sidecar)" no "an allowed use uv does not run a .envrc.local added after the allow"
assert_eq "$UV_CALLS" "[venv][--allow-existing]"$'\n'"[sync][--quiet]" \
  "an allowed use uv creates the venv, then syncs"
assert_eq "$VENV" "$REPO/.venv" "use uv sets VIRTUAL_ENV to the absolute .venv path"
assert_eq "$FIRST_PATH" "$REPO/.venv/bin" "use uv puts .venv/bin first on PATH"
assert_eq "$PYHOME" unset "use uv unsets PYTHONHOME"

new_direnv_sandbox
allow_envrc 'use venv'
write_marker_script "$WS/repo/.venv/bin/activate" activate
direnv_prompt
assert_eq "$(ran activate)" no "use venv outside a git work tree does not run an existing activate script"
assert_eq "$VENV" "$REPO/.venv" "use venv outside a git work tree keeps an existing .venv"

new_direnv_sandbox
allow_envrc 'use uv'
UV_VENV_FAIL=1 direnv_prompt
assert_eq "$VENV" "" "a failed uv venv leaves VIRTUAL_ENV unset"
assert_eq "$UV_CALLS" "[venv][--allow-existing]" "a failed uv venv stops use uv before uv sync"

new_direnv_sandbox
allow_envrc 'use uv'
write_marker_script "$WS/repo/.venv/bin/activate" activate
git_commit_all
direnv_prompt
assert_eq "$(ran activate)" no "a committed .venv/bin/activate does not run"
assert_contains "$ERR" "git tracks files under .venv" "a tracked .venv fails with the reason"
assert_eq "$UV_CALLS" "" "a tracked .venv stops use uv before any uv call"
assert_eq "$VENV" "" "a tracked .venv leaves VIRTUAL_ENV unset"
assert_eq "$FIRST_PATH" "$WS/bin" "a tracked .venv leaves PATH unchanged"

# A case-insensitive file system serves a tracked .VENV as .venv, and macOS has one.
new_direnv_sandbox
allow_envrc 'use venv'
write_marker_script "$WS/repo/.VENV/bin/python" python
git_commit_all
direnv_prompt
assert_contains "$ERR" "git tracks files under .venv" "a tracked .VENV fails like a tracked .venv"
assert_eq "$UV_CALLS" "" "a tracked .VENV stops use venv before uv venv"

new_direnv_sandbox
allow_envrc 'use venv'
echo .venv >"$WS/repo/.gitignore"
git_commit_all
direnv_prompt
assert_eq "$VENV" "$REPO/.venv" "use venv works in a git work tree with an ignored .venv"
assert_eq "$FIRST_PATH" "$REPO/.venv/bin" "an ignored .venv puts .venv/bin first on PATH"

# use_uv loads the repository's .env first, so .env reaches the check's git call.
for dotenv in GIT_DIR=/nonexistent GIT_LITERAL_PATHSPECS=1; do
  new_direnv_sandbox
  allow_envrc 'use uv'
  write_marker_script "$WS/repo/.venv/bin/python" python
  echo "$dotenv" >"$WS/repo/.env"
  git_commit_all
  direnv_prompt
  assert_contains "$ERR" "git tracks files under .venv" "a repository .env with $dotenv does not hide a tracked .venv"
  assert_eq "$UV_CALLS" "" "a repository .env with $dotenv does not reach uv past a tracked .venv"
done

new_direnv_sandbox
allow_envrc 'use uv'
git_commit_all
echo corrupt >"$WS/repo/.git/index"
direnv_prompt
assert_contains "$ERR" "git cannot list .venv" "a git failure inside a work tree fails with the reason"
assert_eq "$UV_CALLS" "" "a git failure inside a work tree stops use uv before any uv call"
assert_eq "$VENV" "" "a git failure inside a work tree leaves VIRTUAL_ENV unset"

# The check's git call reads $HOME/.gitconfig, and core.fsmonitor there is a
# command. git runs it without STUB_DIR, so its marker path is literal.
new_direnv_sandbox
allow_envrc 'use uv'
mkdir "$WS/repo/h"
echo ": >\"$WS/monitor.ran\"" >"$WS/repo/h/monitor"
chmod +x "$WS/repo/h/monitor"
printf '[core]\n\tfsmonitor = %s\n' "$REPO/h/monitor" >"$WS/repo/h/.gitconfig"
echo HOME=h >"$WS/repo/.env"
git_commit_all
direnv_prompt
assert_eq "$(ran monitor)" no "a .env HOME does not make the check run a repository fsmonitor"

new_direnv_sandbox
allow_envrc 'use uv'
write_marker_script "$WS/repo/.venv/bin/python" python
mkdir "$WS/repo/not a git repository"
echo '[bad' >"$WS/repo/not a git repository/.gitconfig"
echo 'HOME="not a git repository"' >"$WS/repo/.env"
git_commit_all
direnv_prompt
assert_contains "$ERR" "git tracks files under .venv" "a .env HOME named like git's message does not hide a tracked .venv"
assert_eq "$UV_CALLS" "" "a .env HOME named like git's message does not reach uv past a tracked .venv"

new_direnv_sandbox
allow_envrc 'use venv'
git_commit_all
in_direnv_repo git config core.fsmonitor /usr/bin/true
direnv_prompt
assert_eq "$VENV" "$REPO/.venv" "a git warning on stderr does not stop use venv"

# A PATH with no git, and no git work tree: only .env can narrow PATH this far
# and leave direnv itself running.
new_direnv_sandbox
allow_envrc 'use uv'
mkdir "$WS/nogit"
cp "$WS/bin/uv" "$WS/nogit/uv"
ln -s "$(command -v bash)" "$(command -v mkdir)" "$WS/nogit/"
echo "PATH=$WS/nogit" >"$WS/repo/.env"
direnv_prompt
assert_eq "$VENV" "$REPO/.venv" "use uv with no git on PATH has no check to run"

report
