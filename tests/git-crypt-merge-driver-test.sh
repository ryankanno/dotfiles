#!/usr/bin/env bash
# Tests for the git-crypt merge driver, called the way git calls it: from the
# worktree root, with the ancestor, current and other temp paths, the result
# read back from the current one. The repository and git merge-file are real;
# git-crypt is stubbed on PATH as a pass-through, since it is an external tool.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="$ROOT/scripts/executable_git-crypt-merge-driver.sh"
PASS=0 FAIL=0
WS=""
SANDBOXES=()

# The suite runs under set -u only: a failing command is tallied by the
# assert_* helpers, never fatal.
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
assert_ne() {
  if [[ "$1" != "$2" ]]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  unexpectedly: %s\n' "$3" "$1"
  fi
}
assert_contains() {
  if grep -qF -- "$2" <<<"$1"; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  missing: %s\n' "$3" "$2"
  fi
}

# GIT_CRYPT_STUB picks the case: fail-smudge exits 1 with no output on the
# input that matches the file STUB_FAIL_ON, so each decrypt is checked on its
# own; fail-clean exits 1 with no output; and hold parks a clean until the
# test creates the release file.
new_repo() {
  WS="$(mktemp -d "${TMPDIR:-/tmp}/git-crypt-merge-test.XXXXXXXX")"
  SANDBOXES+=("$WS")
  REPO="$WS/repo"
  git init -q "$REPO"
  mkdir -p "$WS/bin"
  cat >"$WS/bin/git-crypt" <<'STUB'
#!/usr/bin/env bash
case "${GIT_CRYPT_STUB:-}:$1" in
  fail-smudge:smudge)
    cat >"$STUB_HOLD/stdin"
    cmp -s "$STUB_HOLD/stdin" "$STUB_FAIL_ON" && exit 1
    exec cat "$STUB_HOLD/stdin"
    ;;
  fail-clean:clean) exit 1 ;;
  hold:clean)
    : >"$STUB_HOLD/held"
    while [[ ! -e "$STUB_HOLD/release" ]]; do sleep 0.1; done
    ;;
esac
exec cat
STUB
  chmod +x "$WS/bin/git-crypt"
  export STUB_HOLD="$WS"
  export GIT_CRYPT_STUB=""
}
# git names its temps .merge_file_XXXXXX in the worktree root.
temps() {
  printf '%b' "$1" >"$REPO/.merge_file_ancestor"
  printf '%b' "$2" >"$REPO/.merge_file_current"
  printf '%b' "$3" >"$REPO/.merge_file_other"
}
listing() { (cd "$REPO" && find . -mindepth 1 | sort); }
drive() {
  (cd "$REPO" && PATH="$WS/bin:$PATH" "$DRIVER" .merge_file_ancestor .merge_file_current .merge_file_other) >"$WS/out.txt" 2>"$WS/err.txt"
  RC=$?
}
result() { cat "$REPO/.merge_file_current"; }
# Byte for byte: a command substitution would hide a lost trailing newline.
result_unchanged() { cmp -s "$WS/orig" "$REPO/.merge_file_current" && echo unchanged; }

echo "driver: a clean merge exits 0 with the merged text in the result"
new_repo
temps 'one\ntwo\nthree\n' 'ONE\ntwo\nthree\n' 'one\ntwo\nTHREE\n'
before="$(listing)"
drive
assert_eq "$RC" 0 "exits 0"
assert_eq "$(result)" "$(printf 'ONE\ntwo\nTHREE')" "the result holds both sides' changes"
assert_eq "$(listing)" "$before" "no plaintext stays in the worktree or the git dir"

echo "driver: a content conflict exits with merge-file's status"
new_repo
temps 'a\nb\nc\nd\ne\n' 'A1\nb\nc\nd\nE1\n' 'A2\nb\nc\nd\nE2\n'
cp "$REPO/.merge_file_current" "$WS/expected"
git merge-file -q -L "current branch" -L "ancestor branch" -L "other branch" "$WS/expected" "$REPO/.merge_file_ancestor" "$REPO/.merge_file_other"
merge_file_rc=$?
drive
assert_eq "$merge_file_rc" 2 "the fixture has two conflicts, unlike a failure's exit 1"
assert_eq "$RC" "$merge_file_rc" "exits with merge-file's conflict count"
assert_eq "$(result)" "$(cat "$WS/expected")" "the result holds the conflict markers"

for side in ancestor current other; do
  echo "driver: a failed decrypt of the $side file exits non-zero and leaves the result alone"
  new_repo
  temps 'one\ntwo\nthree\n' 'ONE\ntwo\nthree\n' 'one\ntwo\nTHREE\n'
  cp "$REPO/.merge_file_current" "$WS/orig"
  before="$(listing)"
  GIT_CRYPT_STUB=fail-smudge STUB_FAIL_ON="$REPO/.merge_file_$side" drive
  assert_ne "$RC" 0 "exits non-zero, so git marks the path conflicted"
  assert_eq "$(result_unchanged)" "unchanged" "the result temp is unchanged"
  assert_contains "$(cat "$WS/err.txt")" "git-crypt smudge failed on the $side file" "stderr names what failed"
  assert_eq "$(listing)" "$before" "no plaintext stays in the worktree or the git dir"
done

echo "driver: a failed clean exits non-zero and leaves the result alone"
new_repo
temps 'one\ntwo\nthree\n' 'ONE\ntwo\nthree\n' 'one\ntwo\nTHREE\n'
cp "$REPO/.merge_file_current" "$WS/orig"
before="$(listing)"
GIT_CRYPT_STUB=fail-clean drive
assert_ne "$RC" 0 "exits non-zero, so git marks the path conflicted"
assert_eq "$(result_unchanged)" "unchanged" "the result temp is unchanged"
assert_contains "$(cat "$WS/err.txt")" "git-crypt clean failed" "stderr names what failed"
assert_eq "$(listing)" "$before" "no plaintext stays in the worktree or the git dir"

echo "driver: a TERM mid-merge removes the plaintext and ends by TERM"
new_repo
temps 'one\ntwo\nthree\n' 'ONE\ntwo\nthree\n' 'one\ntwo\nTHREE\n'
before="$(listing)"
(cd "$REPO" && GIT_CRYPT_STUB=hold PATH="$WS/bin:$PATH" exec "$DRIVER" .merge_file_ancestor .merge_file_current .merge_file_other) >/dev/null 2>&1 &
pid=$!
for _ in $(seq 100); do [[ -e "$WS/held" ]] && break; sleep 0.1; done
assert_eq "$([[ -e "$WS/held" ]] && echo held)" "held" "the driver reached the clean"
during="$(listing)"
new="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$during"))"
assert_eq "$(grep -v '^\./\.git/' <<<"$new" | grep -c .)" 0 "mid-merge, no plaintext is in the worktree"
private="$(grep -E '^\./\.git/[^/]+$' <<<"$new")"
assert_ne "$private" "" "mid-merge, the plaintext is in a new dir under the git dir"
assert_eq "$(cd "$REPO" && find "$private" -maxdepth 0 -type d -perm 700)" "$private" "that dir is mode 0700"
kill -TERM "$pid"
: >"$WS/release"
wait "$pid"
assert_eq "$?" 143 "git sees the same death by TERM as before"
assert_eq "$(listing)" "$before" "no plaintext stays in the worktree or the git dir"

report
