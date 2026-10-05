#!/usr/bin/env bash
# Classifies one finding against a review round's delta: "new" when it sits
# on a line changed since the prior round's head, "reviewed" when it sits on
# code an earlier round already reviewed. pr-review blocks the loop only on
# new or high findings, so the classification lives in tested code rather
# than in an agent's reading of a hunk list.
#
# Interface in:  <round_dir> <path>[:<start>[-<end>]]
# Interface out: "new" or "reviewed" on stdout. A round without a prior
#                head (round 1) and a finding without a line both read as
#                new: what cannot be placed blocks, never the reverse.
# Exit codes: 0 classified; 2 usage or no round.json in the round dir.
set -euo pipefail

usage() {
  printf 'usage: finding-scope.sh <round_dir> <path>[:<start>[-<end>]]\n' >&2
  exit 2
}
[[ $# -eq 2 ]] || usage
dir="$1" spec="$2"
[[ -f "$dir/round.json" ]] || usage
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }

prior=$(jq -r '.range.prior_head // empty' "$dir/round.json")
# The line suffix splits at the last colon, so a path holding a colon stays
# whole.
if [[ -z "$prior" || ! "$spec" =~ ^(.+):([0-9]+)(-([0-9]+))?$ ]]; then
  printf 'new\n'
  exit 0
fi
path="${BASH_REMATCH[1]}" start="${BASH_REMATCH[2]}" end="${BASH_REMATCH[4]:-${BASH_REMATCH[2]}}"

awk -v p="$path" -v s="$start" -v e="$end" '
  {
    i = match($0, /:[0-9]+-[0-9]+$/)
    if (!i || substr($0, 1, i - 1) != p) next
    split(substr($0, i + 1), r, "-")
    if (s + 0 <= r[2] + 0 && e + 0 >= r[1] + 0) { hit = 1; exit }
  }
  END { print (hit ? "new" : "reviewed") }
' "$dir/delta.txt" 2>/dev/null || printf 'new\n'
