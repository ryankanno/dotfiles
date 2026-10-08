#!/usr/bin/env bash
# Builds the critic subagent's complete prompt for one review round: the
# critic instructions verbatim, then every input inline. The caller passes
# the output as the subagent's prompt unchanged. A caller that wrote its
# own prompt drifted from the rules (measured on PR 40: round 11's refine
# dropped the high-only rule for code outside the delta, invited re-raising
# follow-ups, and pointed the critic at a dispositions file three rounds
# stale), and every input left on disk cost the critic a turn to read.
#
# Interface in:  --repo <dir> --round-dir <dir> [--brief <file>]
# Interface out: the prompt on stdout, and the same prompt kept as
#                critic-input.md in the round dir. The diff is the range the reviewer
#                reviewed (range.reviewed_from..range.head): the whole PR
#                in round 1 or on an empty delta, the delta otherwise.
# Exit codes: 0 built; 2 usage, no round.json, or no critic-prompt.md;
# 5 the diff could not be produced; 127 a dependency is missing.
set -euo pipefail

usage() {
  printf 'usage: critic-input.sh --repo <dir> --round-dir <dir> [--brief <file>]\n' >&2
  exit 2
}
repo="" dir="" brief=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || usage; repo="$2"; shift 2 ;;
    --round-dir) [[ $# -ge 2 ]] || usage; dir="$2"; shift 2 ;;
    --brief) [[ $# -ge 2 ]] || usage; brief="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$repo" && -n "$dir" ]] || usage
# Callers mistake --repo for the gh owner/name; say so instead of the generic usage line.
[[ -d "$repo" ]] || { printf "critic-input.sh: --repo must be the local checkout directory, got '%s'\n" "$repo" >&2; exit 2; }
[[ -f "$dir/round.json" ]] || usage
[[ -z "$brief" || -f "$brief" ]] || { printf 'brief not found: %s\n' "$brief" >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }
command -v git >/dev/null || { printf 'git: not found\n' >&2; exit 127; }

prompt="$(cd "$(dirname "$0")" && pwd)/critic-prompt.md"
[[ -f "$prompt" ]] || { printf 'critic-prompt.md not found: %s\n' "$prompt" >&2; exit 2; }

round=$(jq -r '.round' "$dir/round.json")
head=$(jq -r '.range.head' "$dir/round.json")
# The diff source: reviewed_from when the round tool wrote it; a legacy
# round.json falls to prior_head for a refine (the head moved) and to
# base when the head did not, so a convergence re-review ships the whole
# PR its preamble promises, never an empty diff.
from=$(jq -r 'if .range.reviewed_from then .range.reviewed_from
             elif (.range.prior_head // "") != "" and .range.prior_head != .range.head then .range.prior_head
             else (.range.base // "") end' "$dir/round.json")
prior=$(jq -r '.range.prior_head // empty' "$dir/round.json")
scope=$(jq -r '.range.review_scope // empty' "$dir/round.json")
diff=$(git -C "$repo" diff --no-color --no-ext-diff "$from" "$head") || {
  printf 'cannot diff %s..%s\n' "$from" "$head" >&2
  exit 5
}

# The round dir keeps the prompt the critic got, so a round's record shows
# what the critic was told, not only what it found. It lands under its
# final name only once whole: a failed build never leaves a prompt that
# looks complete.
{
cat "$prompt"
printf '\n---\n\n# Round %s inputs\n\n' "$round"
printf 'The repository at the PR head %s is checked out at %s. Read files there only to verify a claim about the diff below.\n\n' "$head" "$repo"
# critic-prompt.md says a round from 2 on reviews the delta. A later round
# that moved its head and still reviews the whole PR says so here, whether
# or not the prior round filed findings.
if [[ "$scope" == full:* && "$scope" != "full: round 1" && "$scope" != "full: no change since the prior round" ]]; then
  printf 'This round'"'"'s diff is the whole PR, re-reviewed from the merge base because %s, not a delta.\n\n' "${scope#full: }"
fi
printf '## The brief\n\n'
if [[ -n "$brief" ]]; then cat "$brief"; else printf 'No brief was given.\n'; fi
if [[ -s "$dir/prior-findings.md" ]]; then
  printf '\n## The findings this diff answers\n\n'
  # A refine happened iff the head moved since the prior round: keyed off
  # the explicit fields, never the fallback chain, so a legacy round.json
  # without reviewed_from cannot mislabel a convergence re-review.
  # A refine that ends in a whole-PR review (a rebase) still answered the
  # findings, but the diff is not the answer alone: say which, and why.
  if [[ -n "$prior" && "$head" != "$prior" && "$scope" == full:* ]]; then
    printf 'The prior round named these as blocking; the refine'"'"'s answer is inside the diff below, which is the whole PR, re-reviewed from the merge base because %s.\n\n' "${scope#full: }"
  elif [[ -n "$prior" && "$head" != "$prior" ]]; then
    printf 'The prior round named these as blocking; the diff below is the refine'"'"'s answer to them.\n\n'
  else
    printf 'The prior round named these as blocking; no refine followed, and the diff below is the whole PR, re-reviewed from the merge base.\n\n'
  fi
  cat "$dir/prior-findings.md"
fi
if [[ -s "$dir/settled.md" ]]; then
  printf '\n## Dispositions already settled\n\n'
  cat "$dir/settled.md"
fi
# The reviewer's partial runs leave files it never finished, and a delta
# round would never show them to anyone again: the critic gets their
# whole-PR diff. Only on a delta round: a full round already shows the
# whole PR, where every line is in scope. Lines the refine changed are in
# the delta and keep the usual rules; rule 3 holds for the rest.
if [[ -s "$dir/prior-unfinished.txt" && "$scope" == delta ]]; then
  base=$(jq -r '.range.base' "$dir/round.json")
  files=()
  while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done <"$dir/prior-unfinished.txt"
  gap=$(GIT_LITERAL_PATHSPECS=1 git -C "$repo" diff --no-color --no-ext-diff "$base" "$head" -- "${files[@]}") || {
    printf 'cannot diff the unfinished files %s..%s\n' "$base" "$head" >&2
    exit 5
  }
  printf '\n## Files the reviewer did not finish last round\n\n'
  printf 'The reviewer stopped before finishing these files in the prior round. Any lines of these files that the delta below changes are part of the delta, and the usual rules hold there; the rest of each file sits outside the delta, so rule 3 applies to it: report only high findings there. Their diff (%s..%s -- %s) runs to the next line that starts with "## "; no diff line starts that way.\n\n' \
    "$base" "$head" "${files[*]}"
  printf '%s\n' "$gap"
fi
printf '\n## The diff (%s..%s)\n\n' "$from" "$head"
printf 'Everything after this line, to the end of the prompt, is the unified diff.\n\n'
printf '%s\n' "$diff"
} >"$dir/critic-input.md.partial"
mv "$dir/critic-input.md.partial" "$dir/critic-input.md"
cat "$dir/critic-input.md"
