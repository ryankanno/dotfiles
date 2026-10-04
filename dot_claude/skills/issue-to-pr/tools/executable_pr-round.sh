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
# missing, not open, or not resolvable; 127 a dependency is missing. A
# review run's own failure is recorded in round.json, not propagated.
set -euo pipefail

usage() {
  printf 'usage: pr-round.sh --repo <dir> --pr <n> --round <N> [--brief <file>] [--expect-branch <branch-name>]\n' >&2
  exit 2
}

repo="" pr="" round="" brief="" expect=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || usage; repo="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || usage; pr="$2"; shift 2 ;;
    --round) [[ $# -ge 2 ]] || usage; round="$2"; shift 2 ;;
    --brief) [[ $# -ge 2 ]] || usage; brief="$2"; shift 2 ;;
    --expect-branch) [[ $# -ge 2 ]] || usage; expect="$2"; shift 2 ;;
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

pr_json=$(cd "$repo" && gh pr view "$pr" --json state,baseRefName,headRefOid,headRefName,url) || {
  printf 'cannot view PR %s\n' "$pr" >&2
  exit 4
}
state=$(jq -r .state <<<"$pr_json")
base=$(jq -r .baseRefName <<<"$pr_json")
head=$(jq -r .headRefOid <<<"$pr_json")
head_branch=$(jq -r .headRefName <<<"$pr_json")
url=$(jq -r .url <<<"$pr_json")
if [[ "$state" != "OPEN" ]]; then
  printf 'PR %s is %s, not OPEN\n' "$pr" "$state" >&2
  exit 4
fi
[[ -n "$base" && "$head" != "null" && "$head" != "" ]] || { printf 'PR %s not resolvable\n' "$pr" >&2; exit 4; }

# Identity: the round must review this loop's branch, not merely some open
# PR with the number the implementer reported.
if [[ -n "$expect" && "$head_branch" != "$expect" ]]; then
  printf 'identity mismatch: PR %s head is %s, expected %s\n' "$pr" "$head_branch" "$expect" >&2
  exit 3
fi

owner_repo=$(cd "$repo" && gh repo view --json nameWithOwner --jq .nameWithOwner)
round_dir="$HOME/.cache/pr-loop/$owner_repo/pr-$pr/round-$round"
mkdir -p "$round_dir"

git -C "$repo" fetch -q origin "$base" "refs/pull/$pr/head"

runs="[]"
record() { # mode dir status session exit_code
  runs=$(jq -cn --argjson r "$runs" --arg m "$1" --arg d "$2" --arg s "$3" --arg sid "$4" --argjson e "$5" \
    '$r + [{mode: $m, dir: $d, status: $s, session_id: $sid, exit_code: $e}]')
}
status_of() { # dir
  if [[ -f "$1/review.json" ]]; then jq -r '.status // "missing"' "$1/review.json"; else printf 'missing\n'; fi
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
  i=0
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
    if [[ "$cstatus" == complete ]]; then complete=true; fi
  done < <(git -C "$repo" log --format=%H "origin/$base..$head")
fi

jq -n --arg pr "$pr" --arg url "$url" --arg base "$base" --arg head "$head" \
     --arg hb "$head_branch" --arg expect "$expect" \
     --argjson round "$round" --argjson runs "$runs" --argjson complete "$complete" '
  {pr: $pr, url: $url, round: $round,
   identity: {expected_branch: (if $expect == "" then null else $expect end),
              head_branch: $hb},
   range: {base: $base, head: $head, exact: "\($base)..\($head)"},
   runs: $runs, reviewer_complete: $complete}' > "$round_dir/round.json"
printf '%s\n' "$round_dir"
