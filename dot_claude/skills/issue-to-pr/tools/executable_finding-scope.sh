#!/usr/bin/env bash
# Classifies one finding against a review round's delta: "new" when it sits
# on a line changed since the prior round's head, "reviewed" when it sits on
# code an earlier round already reviewed. pr-review blocks the loop only on
# new or high findings, so the classification lives in tested code rather
# than in an agent's reading of a hunk list.
#
# Interface in:  <round_dir> <path>[:<start>[-<end>]]
# Interface out: "new" or "reviewed" on stdout. A round without a prior
#                head (round 1), a round pr-round.sh wrote no delta for
#                (a rebase, a prior head missing from the clone), and a finding
#                without a line all read as new: what cannot be placed
#                blocks, never the reverse.
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
if [[ -z "$prior" || ! -f "$dir/delta.txt" || ! "$spec" =~ ^(.+):([0-9]+)(-([0-9]+))?$ ]]; then
  printf 'new\n'
  exit 0
fi
path="${BASH_REMATCH[1]}" start="${BASH_REMATCH[2]}" end="${BASH_REMATCH[4]:-${BASH_REMATCH[2]}}"

# The path goes through the environment: -v expands escape sequences, and
# a path may hold a backslash.
p="$path" awk -v s="$start" -v e="$end" '
  { line[NR] = $0 }
  END {
    # A path that holds a newline spans lines, and a segment of it can end
    # in a range suffix too: the line format cannot show where such a path
    # ends. An entry starts on the first line or after a line with a range
    # suffix, so the path looked for is tried from each such start.
    n = split(ENVIRON["p"], seg, "\n")
    for (k = 1; k + n - 1 <= NR; k++) {
      if (k > 1 && !match(line[k - 1], /:[0-9]+-[0-9]+$/)) continue
      for (j = 1; j < n && line[k + j - 1] == seg[j]; j++) ;
      if (j < n) continue
      last = line[k + n - 1]
      i = match(last, /:[0-9]+-[0-9]+$/)
      if (!i || substr(last, 1, i - 1) != seg[n]) continue
      split(substr(last, i + 1), r, "-")
      if (s + 0 <= r[2] + 0 && e + 0 >= r[1] + 0) { hit = 1; break }
    }
    print (hit ? "new" : "reviewed")
  }
' "$dir/delta.txt" 2>/dev/null || printf 'new\n'
