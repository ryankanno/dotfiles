#!/usr/bin/env bash
# What a resume needs from a PR's earlier rounds: the refine count and the
# kind of the newest finished round, read from rounds.txt, where
# pr-round.sh appends one "<N> <kind>" line per round. The round numbers
# alone do not give the count: a convergence round takes a number of its
# own.
#
# Interface in:  <owner/repo> <pr>
# Interface out: on stdout, refine_rounds=<count> and
#                newest_finished=<review|refine|convergence|none>. A
#                number's last line gives its kind, and only a number with
#                a round-<N>/ folder counts: a pane that died before its
#                round started left a line for a round that never ran. A
#                round-<N>/ folder past round 1 with no line and no
#                round.json counts as a refine. A round is finished when
#                it has a round.json and a usable comment
#                (round-comment.sh exits 0).
# Exit codes: 0 printed; 1 no rounds.txt; 2 usage, or an unusable
#             environment (HOME unset, no round-comment.sh); 5 a round
#             comment could not be read (stderr names round-comment.sh's
#             exit).
set -euo pipefail

usage() {
  printf 'usage: resume-state.sh <owner/repo> <pr>\n' >&2
  exit 2
}
[[ $# -eq 2 ]] || usage
owner_repo="$1" pr="$2"
[[ "$owner_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && "$pr" =~ ^[0-9]+$ ]] || usage
if [[ -z "${HOME:-}" ]]; then
  printf 'HOME is not set; the round folder cannot live anywhere\n' >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
# Deployed trees strip the executable_ prefix; the source repo keeps it.
round_comment="$here/round-comment.sh"
[[ -f "$round_comment" ]] || round_comment="$here/executable_round-comment.sh"
[[ -f "$round_comment" ]] || { printf 'round-comment.sh not found in %s\n' "$here" >&2; exit 2; }
pd="$HOME/.cache/pr-loop/$owner_repo/pr-$pr"
[[ -f "$pd/rounds.txt" ]] || { printf 'no rounds.txt in %s: the refine count is unknown\n' "$pd" >&2; exit 1; }

# One "<number> <folder number> <kind>" line per round, newest first.
rounds=$(awk '/^[0-9]+ (review|refine|convergence)$/ { kind[$1 + 0] = $2; dir[$1 + 0] = $1 }
              END { for (n in kind) print n, dir[n], kind[n] }' "$pd/rounds.txt" | sort -rn)
refines=0 newest=none
while read -r n raw kind; do
  [[ -n "$n" && -d "$pd/round-$raw" ]] || continue
  if [[ "$kind" == refine ]]; then refines=$((refines + 1)); fi
  [[ "$newest" == none && -f "$pd/round-$raw/round.json" ]] || continue
  rc=0
  "$round_comment" "$owner_repo" "$pr" "$n" >/dev/null || rc=$?
  case $rc in
    0) newest="$kind" ;;
    1) ;;
    *)
      printf 'cannot read the round %s comment (round-comment.sh exit %s)\n' "$n" "$rc" >&2
      exit 5 ;;
  esac
done <<<"$rounds"
# A refine writes round-<N>/ before its round runs (pr-refine §6), and a
# round that stops before pr-round.sh takes its lock writes no line.
lined=" $(cut -d' ' -f1 <<<"$rounds" | tr '\n' ' ')"
for d in "$pd"/round-*; do
  raw="${d##*/round-}"
  [[ -d "$d" && "$raw" =~ ^[0-9]+$ && $((10#$raw)) -gt 1 && ! -f "$d/round.json" ]] || continue
  [[ "$lined" == *" $((10#$raw)) "* ]] || refines=$((refines + 1))
done
printf 'refine_rounds=%s\nnewest_finished=%s\n' "$refines" "$newest"
