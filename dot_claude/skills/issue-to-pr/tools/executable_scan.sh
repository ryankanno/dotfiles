#!/usr/bin/env bash
# The leak gate every round comment passes before it leaves the machine.
# It lives in tested code because a missed hit is unrecoverable once posted,
# and an unattended agent paraphrasing a prose regex is how hits get missed.
#
# Interface in:  <file>, the comment body.
# Interface out: the file rewritten in place with $HOME as ~; every hit that
#                remains printed as <line>:<text>.
# Exit codes: 0 clean, post it; 1 hits, do not post; 2 usage.
set -euo pipefail

file="${1:-}"
[[ -n "$file" && -f "$file" ]] || {
  printf 'usage: scan.sh <comment body file>\n' >&2
  exit 2
}

body="$(<"$file")"
printf '%s\n' "${body//"$HOME"/\~}" >"$file"

# Token patterns require the variable part (a key body). Home and temp
# patterns require the first path segment (a username, a scratch name,
# an ssh key); the fixed macOS prefixes are bare by design: over-blocking
# prose is recoverable, a leaked path is not.
pattern='/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|/tmp/[A-Za-z0-9._-]+|/root/[A-Za-z0-9._-]+'
pattern+='|/run/user/[0-9]+|/private/|/var/folders/'
pattern+='|sk-[A-Za-z0-9_-]{20,}|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
pattern+='|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}'
pattern+='|npm_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[Bb]earer [A-Za-z0-9._~+/=-]{20,}'

if grep -nE "$pattern" "$file"; then exit 1; fi
exit 0
