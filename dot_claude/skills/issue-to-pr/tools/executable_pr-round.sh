#!/usr/bin/env bash
# The reviewer slot's PR-round entry point: resolve a pull request's exact
# range, bind the round to this loop's branch when asked, run the active
# reviewer binding over the range, apply the per-commit empty-retry policy,
# and write round.json. The skills call this script instead of restating
# range mechanics, so the range contract and the identity check live in
# tested code rather than in prose an agent might paraphrase.
#
# Interface in:  --repo <dir> --pr <n> --round <N> [--brief <file>]
#                [--expect-branch <branch-name>]
# Interface out: the round directory under
#                $HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/ with
#                each run's outputs plus round.json (range, identity, runs,
#                reviewer_complete), and the directory path on stdout.
# Exit codes: 0 the round ran; 2 usage; 3 identity mismatch; 4 the PR is
# missing, not open, or not resolvable; 5 the repository or its refs could
# not be resolved on the network; 6 the round dir already holds
# evidence and --rerun was not passed; 127 a dependency is missing. A
# review run's own failure is recorded in round.json, not propagated.
set -euo pipefail

usage() {
  printf 'usage: pr-round.sh --repo <dir> --pr <n> --round <N> [--brief <file>] [--expect-branch <branch-name>] [--rerun]\n' >&2
  exit 2
}

repo="" pr="" round="" brief="" expect="" rerun=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || usage; repo="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || usage; pr="$2"; shift 2 ;;
    --round) [[ $# -ge 2 ]] || usage; round="$2"; shift 2 ;;
    --brief) [[ $# -ge 2 ]] || usage; brief="$2"; shift 2 ;;
    --expect-branch) [[ $# -ge 2 ]] || usage; expect="$2"; shift 2 ;;
    --rerun) rerun=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "$repo" && -n "$pr" && -n "$round" && -d "$repo" ]] || usage
case "$repo" in /*) ;; *) printf 'repo must be an absolute path\n' >&2; exit 2 ;; esac
[[ "$pr" =~ ^[0-9]+$ ]] || usage
[[ "$round" =~ ^[0-9]+$ ]] || usage
if [[ -n "$brief" ]]; then
  case "$brief" in /*) ;; *) printf 'brief must be an absolute path\n' >&2; exit 2 ;; esac
  [[ -f "$brief" ]] || { printf 'brief not found: %s\n' "$brief" >&2; exit 2; }
fi
command -v gh >/dev/null || { printf 'gh: not found\n' >&2; exit 127; }
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }
command -v git >/dev/null || { printf 'git: not found\n' >&2; exit 127; }

here="$(cd "$(dirname "$0")" && pwd)"
manifest="$here/manifest.json"
[[ -f "$manifest" ]] || { printf 'manifest not found: %s\n' "$manifest" >&2; exit 2; }
reviewer=$(jq -r '.reviewer // empty' "$manifest")
[[ -n "$reviewer" ]] || { printf 'manifest names no reviewer\n' >&2; exit 2; }
# Deployed trees strip the executable_ prefix; the source repo keeps it.
review=""
for cand in "$here/$reviewer/review.sh" "$here/$reviewer/executable_review.sh"; do
  if [[ -f "$cand" ]]; then review="$cand"; break; fi
done
[[ -n "$review" ]] || { printf 'reviewer binding has no review.sh: %s\n' "$reviewer" >&2; exit 2; }

pr_json=$(cd "$repo" && gh pr view "$pr" --json state,baseRefName,headRefOid,headRefName,isCrossRepository,url) || {
  printf 'cannot view PR %s\n' "$pr" >&2
  exit 4
}
state=$(jq -r .state <<<"$pr_json")
base=$(jq -r .baseRefName <<<"$pr_json")
head=$(jq -r .headRefOid <<<"$pr_json")
head_branch=$(jq -r .headRefName <<<"$pr_json")
cross=$(jq -r '.isCrossRepository // false' <<<"$pr_json")
url=$(jq -r .url <<<"$pr_json")
if [[ "$state" != "OPEN" ]]; then
  printf 'PR %s is %s, not OPEN\n' "$pr" "$state" >&2
  exit 4
fi
[[ -n "$base" && "$head" != "null" && "$head" != "" ]] || { printf 'PR %s not resolvable\n' "$pr" >&2; exit 4; }

# Identity: the round must review this loop's branch, not merely some open
# PR with the number the implementer reported. A fork can carry the same
# branch name, so the head must also live in this repository.
if [[ -n "$expect" && "$head_branch" != "$expect" ]]; then
  printf 'identity mismatch: PR %s head is %s, expected %s\n' "$pr" "$head_branch" "$expect" >&2
  exit 3
fi
if [[ -n "$expect" && "$cross" == true ]]; then
  printf 'identity mismatch: PR %s head %s is on a fork\n' "$pr" "$head_branch" >&2
  exit 3
fi

owner_repo=$(cd "$repo" && gh repo view --json nameWithOwner --jq .nameWithOwner) || {
  printf 'cannot resolve the repository at %s\n' "$repo" >&2
  exit 5
}
round_dir="$HOME/.cache/pr-loop/$owner_repo/pr-$pr/round-$round"
mkdir -p "$round_dir"

# The refs resolve before any prior evidence is touched: a network or
# resolution failure must leave the round dir exactly as it was, not
# half-superseded with the old round.json already moved away.
git -C "$repo" fetch -q origin "$base" "refs/pull/$pr/head" || {
  printf 'cannot fetch the PR refs from origin\n' >&2
  exit 5
}
# round.json records the base by SHA, not by a moving branch name: the
# reviewer runs in merge-base mode, so the recorded base is the merge
# base, which stays put for a given head whatever main did in between.
base_sha=$(git -C "$repo" merge-base "origin/$base" "$head") || {
  printf 'cannot resolve the merge base of origin/%s and %s\n' "$base" "$head" >&2
  exit 5
}

# Evidence is never silently overwritten or reused: a re-invocation into a
# round that already holds anything besides superseded runs, including the
# leftovers of an interrupted run with no round.json, is refused unless
# --rerun moves it into a superseded-*/ subdirectory first.
leftovers=()
for f in "$round_dir"/*; do
  if [[ -e "$f" && "$(basename "$f")" != superseded-* ]]; then leftovers+=("$f"); fi
done
if [[ ${#leftovers[@]} -gt 0 ]]; then
  if [[ -z "$rerun" ]]; then
    printf 'round dir already holds evidence; pass --rerun to supersede it\n' >&2
    exit 6
  fi
  keep="$round_dir/superseded-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$keep"
  mv "${leftovers[@]}" "$keep/"
fi

runs="[]"
record() { # mode dir status session exit_code
  runs=$(jq -cn --argjson r "$runs" --arg m "$1" --arg d "$2" --arg s "$3" --arg sid "$4" --argjson e "$5" \
    '$r + [{mode: $m, dir: $d, status: $s, session_id: $sid, exit_code: $e}]')
}
status_of() { # dir
  # A corrupt review.json (truncated mid-write by a failing reviewer) reads
  # as missing, so the round records the gap instead of aborting after the
  # billed run with no round.json at all.
  if [[ -f "$1/review.json" ]]; then
    jq -r '.status // "missing"' "$1/review.json" 2>/dev/null || printf 'missing\n'
  else printf 'missing\n'; fi
}

set +e
"$review" --repo "$repo" --out "$round_dir" ${brief:+--brief "$brief"} --base "origin/$base" --head "$head"
rc=$?
set -e
range_status=$(status_of "$round_dir")
record range "$round_dir" "$range_status" "$(cat "$round_dir/session.txt" 2>/dev/null || true)" "$rc"
if [[ "$range_status" == complete ]]; then
  complete=true
else
  complete=false
  # Empty or incomplete range result: retry once per commit in the range.
  # The round is complete only when every commit run completed; one
  # success among failures is partial coverage, never a clean review.
  i=0 recovered=1 commit_runs=0
  while read -r sha; do
    [[ -n "$sha" ]] || continue
    i=$((i + 1))
    commit_dir="$round_dir/commit-$i"
    set +e
    "$review" --repo "$repo" --out "$commit_dir" ${brief:+--brief "$brief"} --commit "$sha"
    crc=$?
    set -e
    cstatus=$(status_of "$commit_dir")
    record "commit:$sha" "$commit_dir" "$cstatus" "$(cat "$commit_dir/session.txt" 2>/dev/null || true)" "$crc"
    commit_runs=$((commit_runs + 1))
    [[ "$cstatus" == complete ]] || recovered=0
  done < <(git -C "$repo" log --format=%H "origin/$base..$head")
  if [[ $commit_runs -gt 0 && $recovered -eq 1 ]]; then complete=true; fi
fi

tokens_in() { # round.json -> the round's reviewer tokens
  local total=0 t d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    t=$(jq -r '.summary.total_tokens // 0' "$d/review.json" 2>/dev/null || printf '0')
    total=$((total + t))
  done < <(jq -r '.runs[].dir' "$1" 2>/dev/null)
  printf '%s\n' "$total"
}

current_tokens=0
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  t=$(jq -r '.summary.total_tokens // 0' "$d/review.json" 2>/dev/null || printf '0')
  current_tokens=$((current_tokens + t))
done < <(jq -r '.[].dir' <<<"$runs")

prior_tokens=0
for sibling in "$HOME/.cache/pr-loop/$owner_repo/pr-$pr"/round-*/round.json; do
  [[ -f "$sibling" ]] || continue
  n="${sibling%/round.json}"; n="${n##*/round-}"
  # Base 10: a zero-padded round-08 is a decimal 8, not an octal error the
  # || continue would silently drop from the cumulative cost.
  [[ "$n" =~ ^[0-9]+$ && $((10#$n)) -lt $((10#$round)) ]] || continue
  t=$(jq -r '.round_tokens // 0' "$sibling" 2>/dev/null || printf '0')
  if [[ "$t" == 0 ]]; then t=$(tokens_in "$sibling"); fi
  prior_tokens=$((prior_tokens + t))
done

jq -n --arg pr "$pr" --arg url "$url" --arg base "$base" --arg base_sha "$base_sha" --arg head "$head" \
     --arg hb "$head_branch" --arg expect "$expect" \
     --argjson round "$((10#$round))" --argjson runs "$runs" --argjson complete "$complete" \
     --argjson rt "$current_tokens" --argjson ct "$((current_tokens + prior_tokens))" '
  {pr: $pr, url: $url, round: $round,
   identity: {expected_branch: (if $expect == "" then null else $expect end),
              head_branch: $hb},
   range: {base: $base_sha, base_branch: $base, head: $head, exact: "\($base_sha)..\($head)"},
   runs: $runs, reviewer_complete: $complete,
   round_tokens: $rt, cumulative_tokens: $ct}' > "$round_dir/round.json"
printf '%s\n' "$round_dir"
