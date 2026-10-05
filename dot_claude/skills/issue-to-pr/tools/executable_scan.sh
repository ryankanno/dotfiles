#!/usr/bin/env bash
# The leak gate every round comment passes before it leaves the machine.
# It lives in tested code because a missed hit is unrecoverable once posted,
# and an unattended agent paraphrasing a prose regex is how hits get missed.
#
# Interface in:  <file>, the comment body.
# Interface out: the file rewritten in place with $HOME as ~; every hit that
#                remains printed as <line>:<text>.
# Exit codes: 0 clean, post it; 1 hits, do not post; 2 usage, or the scan
#              itself failed (an unreadable file, a broken pattern): also
#              do not post.
set -euo pipefail

file="${1:-}"
[[ -n "$file" && -f "$file" ]] || {
  printf 'usage: scan.sh <comment body file>\n' >&2
  exit 2
}

# The tilde rides in a variable: bash 3.2 keeps the escaped form literal in
# the replacement, and every posted comment from a stock macOS would carry
# a stray backslash before the redacted path.
tilde='~'
body="$(<"$file")"
printf '%s\n' "${body//"$HOME"/$tilde}" >"$file"

# Token patterns require the variable part (a key body). Home and temp
# patterns require the first path segment (a username, a scratch name,
# an ssh key); the fixed macOS prefixes are bare by design: over-blocking
# prose is recoverable, a leaked path is not. The AWS secret rule is
# anchored on the key's own name, so a forty-hex sha is not a hit.
pattern='/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|/tmp/[A-Za-z0-9._-]+|/root/[A-Za-z0-9._-]+'
pattern+='|/run/user/[0-9]+|/private/|/var/folders/'
pattern+='|sk-[A-Za-z0-9_-]{20,}|sk_live_[0-9a-zA-Z]{24,}|AIza[0-9A-Za-z_-]{35}'
pattern+='|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
pattern+='|(aws_secret_access_key|AWS_SECRET_ACCESS_KEY)[[:space:]]*[=:][[:space:]]*["]?[A-Za-z0-9/+=]{40}'
pattern+='|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}'
pattern+='|npm_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[Bb]earer [A-Za-z0-9._~+/=-]{20,}'

# grep's own failure (an unreadable file, a broken pattern) is a blocked
# post, never a silent pass.
rc=0
grep -nE "$pattern" "$file" || rc=$?
case "$rc" in
  0) exit 1 ;;
  1) exit 0 ;;
  *) printf 'scan failed (grep exit %s)\n' "$rc" >&2; exit 2 ;;
esac
