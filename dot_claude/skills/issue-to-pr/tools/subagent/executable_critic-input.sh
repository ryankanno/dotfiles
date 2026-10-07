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
# Interface out: the prompt on stdout. The diff is the range the reviewer
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
[[ -n "$repo" && -d "$repo" && -n "$dir" && -f "$dir/round.json" ]] || usage
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

cat "$prompt"
printf '\n---\n\n# Round %s inputs\n\n' "$round"
printf 'The repository at the PR head %s is checked out at %s. Read files there only to verify a claim about the diff below.\n\n' "$head" "$repo"
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
printf '\n## The diff (%s..%s)\n\n' "$from" "$head"
printf 'Everything after this line, to the end of the prompt, is the unified diff.\n\n'
printf '%s\n' "$diff"
