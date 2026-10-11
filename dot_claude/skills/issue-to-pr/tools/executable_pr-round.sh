#!/usr/bin/env bash
# The reviewer slot's PR-round entry point: resolve a pull request's exact
# range, bind the round to this loop's branch when asked, run the active
# reviewer binding over the range, apply the per-commit empty-retry policy,
# and write round.json. The skills call this script instead of restating
# range mechanics, so the range contract and the identity check live in
# tested code rather than in prose an agent might paraphrase.
#
# Interface in:  --repo <dir> --pr <n> --round <N> [--brief <file>]
#                [--dispositions <file>] [--expect-branch <branch-name>]
#                [--effort low|medium|high] [--timeout <minutes>]
#                [--max-tools <n>] [--max-tokens-budget <n>] (passed
#                to every review run; the binding owns the defaults)
#                [--rerun] [--convergence: a base merge with no PR change
#                reviews the whole PR instead of nothing]
# Interface out: the round directory under
#                $HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/ with
#                each run's outputs plus round.json (range, identity, runs,
#                reviewer_complete, range.prior_head, range.reviewed_from:
#                the prior head on a delta round, or after a base merge
#                a baseline commit (the prior head merged onto the new
#                merge base), the merge base otherwise,
#                range.review_scope: "delta", "full: <why>", or
#                "none: <why>" when a base merge alone moved the head and
#                no reviewer runs),
#                delta.txt from round 2 on, unless a rebase, an unusable
#                prior head, or a change that adds or modifies no lines (a
#                deletion-only, binary-only or mode-only change, issue #56)
#                sends the round to the whole PR (the
#                path:start-end hunks changed since range.reviewed_from;
#                empty when the tree did not change: the same head, an
#                empty commit or a revert pair, issue #43) with names.txt
#                (the listing the hunks
#                enumerate over), settled.md (the standing Rejected and
#                Accepted lines) and prior-findings.md (the newest earlier-round
#                comment's blocking findings) and prior-unfinished.txt (the
#                files the prior round's reviewer did not finish) when
#                there are any, which critic-input.sh reads, background.md
#                when there are prior
#                dispositions (read from this loop's own round comments
#                unless --dispositions names a file; newest first within
#                the manifest's reviewer_background_limit), and the
#                directory path on stdout.
# Exit codes: 0 the round ran; 2 usage, the environment is unusable
# (HOME unset), or the brief cannot fit the reviewer's background limit,
# alone or once the standing dispositions assemble into it; 3 identity
# mismatch; 4 the PR is
# missing, not open, or not resolvable; 5 the repository, its refs, or
# the changed-file listing could not be resolved; 6 the round dir already holds
# evidence and --rerun was not passed; 127 a dependency is missing. A
# review run's own failure is recorded in round.json, not propagated.
set -euo pipefail

usage() {
  printf 'usage: pr-round.sh --repo <dir> --pr <n> --round <N> [--brief <file>] [--dispositions <file>] [--expect-branch <branch-name>] [--effort low|medium|high] [--timeout <minutes>] [--max-tools <n>] [--max-tokens-budget <n>] [--rerun] [--convergence]\n' >&2
  exit 2
}

repo="" pr="" round="" brief="" dispositions="" expect="" rerun="" effort="" timeout="" max_tools="" token_budget="" convergence=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || usage; repo="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || usage; pr="$2"; shift 2 ;;
    --round) [[ $# -ge 2 ]] || usage; round="$2"; shift 2 ;;
    --brief) [[ $# -ge 2 ]] || usage; brief="$2"; shift 2 ;;
    --dispositions) [[ $# -ge 2 ]] || usage; dispositions="$2"; shift 2 ;;
    --expect-branch) [[ $# -ge 2 ]] || usage; expect="$2"; shift 2 ;;
    --effort) [[ $# -ge 2 ]] || usage; effort="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || usage; timeout="$2"; shift 2 ;;
    --max-tools) [[ $# -ge 2 ]] || usage; max_tools="$2"; shift 2 ;;
    --max-tokens-budget) [[ $# -ge 2 ]] || usage; token_budget="$2"; shift 2 ;;
    --rerun) rerun=1; shift ;;
    --convergence) convergence=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "$repo" && -n "$pr" && -n "$round" ]] || usage
# Checked here, not left to the binding: a value it rejects would fail
# every run of the round and leave a round dir that only --rerun clears.
case "$effort" in ""|low|medium|high) ;; *) usage ;; esac
[[ -z "$timeout" || "$timeout" =~ ^[1-9][0-9]*$ ]] || usage
# The digit caps keep a value inside bash and ocr integers; a longer one
# wraps in bash arithmetic and slips past the floor.
[[ -z "$max_tools" || ( "$max_tools" =~ ^[1-9][0-9]{0,8}$ && max_tools -ge 50 ) ]] || usage
[[ -z "$token_budget" || "$token_budget" =~ ^[1-9][0-9]{0,17}$ ]] || usage
# Callers mistake --repo for the gh owner/name; say so instead of the generic usage line.
[[ -d "$repo" ]] || { printf "pr-round.sh: --repo must be the local checkout directory, got '%s'\n" "$repo" >&2; exit 2; }
case "$repo" in /*) ;; *) printf 'repo must be an absolute path\n' >&2; exit 2 ;; esac
[[ "$pr" =~ ^[0-9]+$ ]] || usage
[[ "$round" =~ ^[0-9]+$ ]] || usage
if [[ -n "$brief" ]]; then
  case "$brief" in /*) ;; *) printf 'brief must be an absolute path\n' >&2; exit 2 ;; esac
  [[ -f "$brief" ]] || { printf 'brief not found: %s\n' "$brief" >&2; exit 2; }
fi
if [[ -n "$dispositions" ]]; then
  case "$dispositions" in /*) ;; *) printf 'dispositions must be an absolute path\n' >&2; exit 2 ;; esac
  [[ -f "$dispositions" ]] || { printf 'dispositions not found: %s\n' "$dispositions" >&2; exit 2; }
fi
command -v gh >/dev/null || { printf 'gh: not found\n' >&2; exit 127; }
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }
command -v git >/dev/null || { printf 'git: not found\n' >&2; exit 127; }

# Like the scan gate: the round dir lives under HOME, so an unset HOME is a
# classified failure callers can act on, not an unbound abort with an
# undocumented code.
if [[ -z "${HOME:-}" ]]; then
  printf 'HOME is not set; the round dir cannot live anywhere\n' >&2
  exit 2
fi

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
# ocr aborts on a background over 8000 characters before reviewing
# anything, and the per-commit retry then repeats the abort once per
# commit (measured on sudoku PR 191: an 11083-character brief, 15 runs, no
# review). Sizes count bytes, never fewer than characters, so a background
# that fits in bytes fits the reviewer's character limit. The guard stops
# a brief that cannot fit alone; the assembly's own check below stops a
# background that overflows once the standing dispositions join it, so
# neither window reaches the reviewer (measured on PR 40: a limit-sized
# brief assembled to limit+264).
dispositions_header=$'## Findings already dispositioned in earlier rounds\n\nEach line was rejected or accepted with recorded evidence. Do not report it again unless the code it cites changed.\n\n'
limit=$(jq -r '.reviewer_background_limit // 0' "$manifest")
if [[ -n "$brief" && "$limit" -gt 0 ]]; then
  brief_size=$(wc -c <"$brief" | tr -d ' ')
  if [[ "$brief_size" -gt "$limit" ]]; then
    printf 'brief is %s bytes; the %s reviewer accepts at most %s characters of background. Condense the brief to the task: its asks, the settled decisions, and the constraints.\n' \
      "$brief_size" "$reviewer" "$limit" >&2
    exit 2
  fi
fi

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

# The reviewer sees only its background file, never the PR comments, so
# without the prior rounds' dispositions it re-raises findings a refine
# already rejected with evidence (measured on PR 40: the same rejected
# finding came back twice in the next round). Only this loop's own round
# comments count, the marker on line 1 and our own author, or anyone who
# can comment on the PR could talk the reviewer out of a real finding.
# Fixed lines stay out: a fix the reviewer still flags needs re-checking.
me=$(gh api user --jq .login) || {
  printf 'cannot resolve the gh user for the prior round comments\n' >&2
  exit 5
}
# The pr view comments field is capped at its first page; the issue
# comments endpoint paginates, so a long PR cannot silently lose the
# standing dispositions. One JSON string per line keeps each body whole.
bodies=$(gh api --paginate "repos/$owner_repo/issues/$pr/comments" \
    --jq '.[] | select(.user.login == "'"$me"'") | select(.body | startswith("<!-- pr-loop-comment -->")) | .body | @json') || {
  printf 'cannot read the PR comments\n' >&2
  exit 5
}
# A rerun of round N must not read round N's or a later round's comment
# (issue #58). A comment without the round heading stays.
bodies=$(jq -c --argjson r "$((10#$round))" \
  'select(((capture("(?m)^## Review round (?<n>[0-9]+):") | .n | tonumber) // 0) < $r)' <<<"$bodies")
if [[ -n "$dispositions" ]]; then
  settled=$(cat "$dispositions")
else
  # A settled entry is the marker line plus its indented continuations;
  # a blank line, another marker, or column-0 prose ends it. Structural
  # lines inside the block ("Round 2's 10 findings, all fixed:") are
  # column-0 prose and never harvest as settled law.
  settled=$(jq -r '.' <<<"$bodies" \
     | awk '/<summary>Dispositions<\/summary>/ { on = 1; next }
           on && /^<\/details>/ { on = 0 }
           on && /^- (Rejected|Accepted):/ { keep = 1; print; next }
           on && /^- / { keep = 0; next }
           on && NF == 0 { keep = 0; next }
           on && keep && /^[[:space:]]/ { print; next }
           on && NF { keep = 0 }')
fi
# The newest earlier-round comment's blocking findings are what this round's
# delta answers. critic-input.sh hands them to the critic verbatim, so the
# critic checks the fixes against the claims, not against a paraphrase.
# A claim can wrap onto continuation lines; every non-blank line of the
# section is kept so a wrapped claim arrives whole.
prior_findings=$(tail -n 1 <<<"$bodies" | jq -r '.' \
  | awk '/^\*\*Findings:\*\*/ { on = 1; next }
         on && (/^\*\*/ || /^<details>/) { on = 0 }
         on && NF')

# The background is assembled and measured before the round dir is touched
# and before any --rerun superseding: a size refusal must leave the dir
# exactly as it was, so the documented recovery (condense and rerun) hits
# no leftover guard, and a refusal of a --rerun displaces no record.
tmp_bg=""
trap '[[ -n "${tmp_bg:-}" ]] && rm -f "$tmp_bg"' EXIT
kept="$settled" omitted=0
if [[ -n "$settled" ]]; then
  tmp_bg=$(mktemp "${TMPDIR:-/tmp}/pr-round-bg.XXXXXX") || {
    printf 'cannot create a temp file for the background\n' >&2
    exit 2
  }
  {
    if [[ -n "$brief" ]]; then cat "$brief"; printf '\n'; fi
    printf '%s' "$dispositions_header"
  } >"$tmp_bg"
  if [[ "$limit" -gt 0 ]]; then
    # Room for the omission line, whatever its count.
    budget=$(( limit - $(wc -c <"$tmp_bg" | tr -d ' ') - 120 ))
    kept=$(printf '%s\n' "$settled" | LC_ALL=C awk -v b="$budget" '
      { l[NR] = $0 }
      /^- / { s[++n] = NR }
      END {
        # No entries: carry the file whole; the assembled-size check
        # bounds it.
        if (n == 0) { for (i = 1; i <= NR; i++) print l[i]; exit }
        # Leading prose rides with the oldest entry: it ships when the
        # oldest entry ships and gives way when it does.
        s[1] = 1
        # An entry is a marker line plus its continuations; whole entries
        # give way, newest first, so the background never ships an
        # orphaned continuation without its claim.
        for (i = 1; i <= n; i++) {
          last = (i < n) ? s[i + 1] - 1 : NR
          sz[i] = 0
          for (j = s[i]; j <= last; j++) sz[i] += length(l[j]) + 1
        }
        used = 0; first = n + 1
        for (i = n; i >= 1; i--) { if (used + sz[i] > b) break; used += sz[i]; first = i }
        for (i = first; i <= n; i++) {
          last = (i < n) ? s[i + 1] - 1 : NR
          for (j = s[i]; j <= last; j++) print l[j]
        }
      }')
    total=$(printf '%s\n' "$settled" | grep -c '^- ' || true)
    kept_n=0
    if [[ -n "$kept" ]]; then kept_n=$(printf '%s\n' "$kept" | grep -c '^- ' || true); fi
    omitted=$(( total - kept_n ))
  fi
  {
    if [[ -n "$kept" ]]; then printf '%s\n' "$kept"; fi
    if [[ "$omitted" -gt 0 ]]; then
      printf '\n(%s older dispositions omitted: the reviewer accepts at most %s characters of background.)\n' "$omitted" "$limit"
    fi
  } >>"$tmp_bg"
  # The honest ceiling: the assembled artifact itself, checked before any
  # review runs and before the round dir is touched, so no reserve
  # arithmetic can reject a background that fits or pass one that does
  # not, and a refusal leaves nothing behind.
  if [[ "$limit" -gt 0 ]]; then
    assembled=$(wc -c <"$tmp_bg" | tr -d ' ')
    if [[ "$assembled" -gt "$limit" ]]; then
      if [[ -n "$brief" ]]; then
        printf 'the assembled background is %s bytes; the brief with the standing dispositions assembles past the %s reviewer'"'"'s %s-character background limit, and the review would abort before reading a line, once per commit. Condense the brief: its asks, the settled decisions, and the constraints.\n' \
          "$assembled" "$reviewer" "$limit" >&2
      else
        printf 'the assembled background is %s bytes; the standing dispositions assemble past the %s reviewer'"'"'s %s-character background limit, and the review would abort before reading a line, once per commit. Condense the standing dispositions: fewer entries or trimmed evidence.\n' \
          "$assembled" "$reviewer" "$limit" >&2
      fi
      exit 2
    fi
  fi
fi

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
  # The PID in the name keeps two reruns of the same round in one
  # wall-clock second from overwriting each other's archive.
  keep="$round_dir/superseded-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$keep"
  mv "${leftovers[@]}" "$keep/"
fi

# Each round reviews the whole PR afresh and keeps finding new edge cases
# in code earlier rounds already reviewed, so the loop never converges
# (measured on PR 40: 24 of 32 findings in rounds 3 to 6). The delta since
# the prior round's head is what a refine round actually has to answer
# for; finding-scope.sh classifies each finding against it.
prior_head="" prior_base="" prior_unfinished=""
for sibling in "$HOME/.cache/pr-loop/$owner_repo/pr-$pr"/round-*/round.json; do
  [[ -f "$sibling" ]] || continue
  n="${sibling%/round.json}"; n="${n##*/round-}"
  [[ "$n" =~ ^[0-9]+$ && $((10#$n)) -eq $((10#$round - 1)) ]] || continue
  prior_head=$(jq -r '.range.head // empty' "$sibling" 2>/dev/null || true)
  prior_base=$(jq -r '.range.base // empty' "$sibling" 2>/dev/null || true)
  # A partial round's failed files go to the next round's critic, not to
  # a whole-PR re-review: the same caps re-fail the same files (issue
  # #41: two files failed in both of a PR's first two rounds).
  # An unreadable prior round.json contributes nothing, as for prior_head,
  # never an aborted round.
  prior_unfinished=$(jq -r '.runs[]?.dir' "$sibling" 2>/dev/null \
    | while IFS= read -r d; do
        jq -r '.manifest.coverage.failed[]?.path // empty' "$d/review.json" 2>/dev/null || true
      done | sort -u || true)
  # A base-merge-only round ran no reviewer, so it has no runs to read:
  # the list it carried passes on, or a base merge would drop it for good.
  if [[ "$(jq -r '.range.review_scope // empty' "$sibling" 2>/dev/null || true)" == none:* ]]; then
    prior_unfinished=$(cat "${sibling%/round.json}/prior-unfinished.txt" 2>/dev/null || true)
  fi
done
if [[ -n "$prior_unfinished" ]]; then printf '%s\n' "$prior_unfinished" >"$round_dir/prior-unfinished.txt"; fi
# The delta stands in for the whole PR only when the new head descends
# from the prior round's head. After a rebase the reviewer's merge-base
# mode would resolve the orphaned prior head to the old base and review
# the base branch's own changes as the PR's (issue #41: 66 files reviewed
# for a 20-file PR), so the round reviews the whole PR from the merge base
# with no delta, and every finding counts as new, which blocks more,
# never less.
scope="delta"
if [[ $((10#$round)) -eq 1 ]]; then
  scope="full: round 1"
elif [[ -z "$prior_head" ]]; then
  scope="full: there is no prior round head on record"
elif ! git -C "$repo" cat-file -e "$prior_head^{commit}" 2>/dev/null; then
  # The head stays on record: the head moved, so the critic is told this
  # is a refine reviewed whole, not a re-review with no refine.
  scope="full: the prior head is not in this clone"
elif ! git -C "$repo" merge-base --is-ancestor "$prior_head" "$head"; then
  scope="full: the branch was rebased since the prior round"
fi
# A merge of the base into the PR keeps the prior head an ancestor, but
# prior_head..head then carries every base change the merge brought in
# (issue #49: 16 of 21 delta hunks on PR 45 were main's). When the merge
# base moved, the delta starts from a baseline commit instead: the prior
# head merged onto the new merge base, so only the PR's own changes since
# the prior round remain, conflict resolutions among them. The reviewer
# diffs in merge-base mode, and the baseline and the head share two
# merge bases, so the reviewer gets a commit with the head's tree whose
# only parent is the baseline. Neither commit is on any ref.
delta_from="$prior_head" delta_to="$head"
if [[ "$scope" == delta && -n "$prior_base" && "$prior_base" != "$base_sha" ]]; then
  # merge-tree exits 1 on a conflict and still writes the merged tree,
  # with the conflict markers in it, on its first line.
  set +e
  merged=$(git -C "$repo" merge-tree --write-tree "$prior_head" "$base_sha")
  mrc=$?
  set -e
  if [[ $mrc -gt 1 ]]; then
    printf "cannot merge the prior head %s onto the merge base %s (git's error is above; merge-tree --write-tree needs git 2.38 or later)\n" "$prior_head" "$base_sha" >&2
    exit 5
  fi
  # A fixed identity: the user's checkout may have none, or sign commits.
  synth() {
    GIT_AUTHOR_NAME=pr-loop GIT_AUTHOR_EMAIL=pr-loop@localhost \
    GIT_COMMITTER_NAME=pr-loop GIT_COMMITTER_EMAIL=pr-loop@localhost \
      git -C "$repo" commit-tree --no-gpg-sign "$@"
  }
  delta_from=$(synth "${merged%%$'\n'*}" -p "$prior_head" -p "$base_sha" \
      -m "pr-loop baseline: $prior_head on merge base $base_sha") \
    && delta_to=$(synth "$head^{tree}" -p "$delta_from" -m "pr-loop head: $head") || {
    printf 'cannot write the baseline commits for the delta\n' >&2
    exit 5
  }
fi
delta=""
if [[ "$scope" == delta ]]; then
  # Hunks enumerate per file because the git header line is inherently
  # ambiguous for paths holding the split sequence itself. Three rules
  # keep the delta exact: the listing's failure is fatal (an unreadable
  # listing is not an unchanged head), every path is passed literally
  # (glob and magic metacharacters in a filename are not pathspec
  # syntax), and a rename's two paths are diffed together so an edit
  # reports as edited ranges, never a whole-file add.
  names="$round_dir/names.txt"
  git -C "$repo" -c core.quotePath=false diff --name-status -M --no-color \
      "$delta_from" "$head" >"$names" || {
    printf 'cannot list the changed files\n' >&2
    exit 5
  }
  : >"$round_dir/delta.txt"
  while IFS=$'\t' read -r status old new; do
    [[ -n "$old" ]] || continue
    # The path reaches awk through the environment, not -v: -v expands
    # escape sequences in the value, and a filename may hold one.
    p="$old"
    paths=("$old")
    if [[ "$status" == R* ]]; then p="$new"; paths+=("$new"); fi
    GIT_LITERAL_PATHSPECS=1 \
      git -C "$repo" -c core.quotePath=false diff -U0 -M --no-color --no-ext-diff \
          "$delta_from" "$head" -- "${paths[@]}" \
      | p="$p" awk '/^@@ / {
          n = split(substr($3, 2), a, ",")
          cnt = (n > 1) ? a[2] : 1
          if (cnt > 0) print ENVIRON["p"] ":" a[1] "-" (a[1] + cnt - 1)
        }' >>"$round_dir/delta.txt"
  done <"$names"
  delta=$(cat "$round_dir/delta.txt")
fi

if [[ -n "$settled" ]]; then printf '%s\n' "$settled" >"$round_dir/settled.md"; fi
if [[ -n "$prior_findings" ]]; then printf '%s\n' "$prior_findings" >"$round_dir/prior-findings.md"; fi

# The background was assembled and size-checked in the temp file above,
# before the round dir was touched; committing it here is safe.
if [[ -n "$settled" ]]; then
  cat "$tmp_bg" >"$round_dir/background.md"
  rm -f "$tmp_bg"
  tmp_bg=""
  brief="$round_dir/background.md"
fi

runs="[]"
record() { # mode dir status session exit_code
  runs=$(jq -cn --argjson r "$runs" --arg m "$1" --arg d "$2" --arg s "$3" --arg sid "$4" --argjson e "$5" \
    '$r + [{mode: $m, dir: $d, status: $s, session_id: $sid, exit_code: $e}]')
}
status_of() { # dir
  # A corrupt review.json (truncated mid-write by a failing reviewer) reads
  # as missing, so the round records the gap instead of aborting after the
  # billed run with no round.json at all. A complete run whose group lost a
  # review pass (review_round_failed) or left failed files still reports
  # every other file completed; both are partial coverage and read as such.
  if [[ -f "$1/review.json" ]]; then
    jq -r 'if .status == "complete"
              and (([.warnings[]? | select(.type == "review_round_failed")] | length) > 0
                   or ((.manifest.coverage.failed // []) | length) > 0)
            then "partial" else .status // "missing" end' "$1/review.json" 2>/dev/null || printf 'missing\n'
  else printf 'missing\n'; fi
}

# From round 2 on the reviewer reads only the delta: a finding outside it
# can only be a follow-up, and the whole-PR review cost 1.7M to 4.6M
# tokens a round on PR 40 to yield one or two blocking findings. An empty
# delta (the same head as the prior round, as in a convergence round)
# reviews the whole PR again: an empty range is no review at all.
review_from="origin/$base" reviewed_from="$base_sha" review_to="$head"
if [[ -n "$delta" ]]; then review_from="$delta_from" reviewed_from="$delta_from" review_to="$delta_to"; fi
# A base merge alone leaves the PR's own code as the prior round reviewed
# it, so the round records that and bills nothing. Nothing reviewed is
# never clean. The trees decide, not the hunks: a deletion-only change
# also leaves the delta empty (issue #43) and is still a change. The
# convergence round still reviews the whole PR: the loop's clean verdict
# must rest on a review of the merged head.
same_tree=1
if [[ "$scope" == delta && "$delta_from" != "$prior_head" ]]; then
  # diff exits 1 when the trees differ; above 1 it failed, and a failure
  # read as "differ" would bill a whole-PR review in silence.
  set +e
  git -C "$repo" diff --quiet --no-ext-diff "$delta_from" "$head"
  same_tree=$?
  set -e
  if [[ $same_tree -gt 1 ]]; then
    printf 'cannot compare the baseline %s with the head %s\n' "$delta_from" "$head" >&2
    exit 5
  fi
fi
if [[ $same_tree -eq 0 ]]; then
  if [[ -z "$convergence" ]]; then
    scope="none: the PR's own code did not change since the prior round (a base merge only)"
    review_from="$delta_from" reviewed_from="$delta_from"
  else
    scope="full: only a base merge since the prior round"
  fi
fi
if [[ "$scope" == delta && -z "$delta" ]]; then
  # A moved tree with no added line (a deletion, a binary or mode change)
  # is a change (issue #56): with no delta.txt every finding blocks as new.
  set +e
  git -C "$repo" diff --quiet --no-ext-diff "$delta_from" "$head"
  moved=$?
  set -e
  if [[ $moved -gt 1 ]]; then
    printf 'cannot compare the prior head %s with the head %s\n' "$delta_from" "$head" >&2
    exit 5
  fi
  if [[ $moved -eq 1 ]]; then
    scope="full: the change since the prior round adds no lines"
    rm -f "$round_dir/delta.txt" "$round_dir/names.txt"
  else
    scope="full: no change since the prior round"
  fi
fi

range_status=none
if [[ "$scope" != none:* ]]; then
  set +e
  "$review" --repo "$repo" --out "$round_dir" ${brief:+--brief "$brief"} ${effort:+--effort "$effort"} ${timeout:+--timeout "$timeout"} ${max_tools:+--max-tools "$max_tools"} ${token_budget:+--max-tokens-budget "$token_budget"} --base "$review_from" --head "$review_to"
  rc=$?
  set -e
  range_status=$(status_of "$round_dir")
  record range "$round_dir" "$range_status" "$(cat "$round_dir/session.txt" 2>/dev/null || true)" "$rc"
fi
if [[ "$range_status" == none ]]; then
  complete=false
elif [[ "$range_status" == complete ]]; then
  complete=true
elif [[ "$range_status" == missing || "$range_status" == skipped ]]; then
  complete=false
  # The range produced no review text, or the tool declined it (a
  # docs-only range): retry once per commit in the range. The round is
  # complete only when every commit run completed; one success among
  # failures is partial coverage, never a clean review.
  # A partial range is NOT retried here: it produced review text, the
  # coverage gap is a fact the comment shows, and one billed commit
  # review per commit in the range does not repair it.
  i=0 recovered=1 commit_runs=0
  while read -r sha; do
    [[ -n "$sha" ]] || continue
    i=$((i + 1))
    commit_dir="$round_dir/commit-$i"
    set +e
    "$review" --repo "$repo" --out "$commit_dir" ${brief:+--brief "$brief"} ${effort:+--effort "$effort"} ${timeout:+--timeout "$timeout"} ${max_tools:+--max-tools "$max_tools"} ${token_budget:+--max-tokens-budget "$token_budget"} --commit "$sha"
    crc=$?
    set -e
    cstatus=$(status_of "$commit_dir")
    record "commit:$sha" "$commit_dir" "$cstatus" "$(cat "$commit_dir/session.txt" 2>/dev/null || true)" "$crc"
    commit_runs=$((commit_runs + 1))
    [[ "$cstatus" == complete ]] || recovered=0
  done < <(git -C "$repo" log --format=%H "$review_from..$review_to")
  if [[ $commit_runs -gt 0 && $recovered -eq 1 ]]; then complete=true; fi
else
  # partial or any other non-complete status: review text exists, some
  # files were not covered. The round records the gap and stays
  # incomplete; it does not re-bill the whole range one commit at a time.
  complete=false
fi

# One summing helper for both shapes, the in-memory runs array and a prior
# round.json's runs: two copies of the arithmetic drift apart, and a
# miscounted cumulative cost never announces itself.
runs_tokens() { # <runs array json> -> the runs' reviewer tokens
  local total=0 t d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    t=$(jq -r '.summary.total_tokens // 0' "$d/review.json" 2>/dev/null || printf '0')
    total=$((total + t))
  done < <(jq -r '.[].dir' <<<"$1" 2>/dev/null)
  printf '%s\n' "$total"
}

tokens_in() { # round.json -> the round's reviewer tokens (legacy, no round_tokens field)
  runs_tokens "$(jq -c '.runs // []' "$1" 2>/dev/null || printf '[]')"
}

current_tokens=$(runs_tokens "$runs")

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
     --arg hb "$head_branch" --arg expect "$expect" --arg prior "$prior_head" --arg from "$reviewed_from" --arg scope "$scope" \
     --argjson round "$((10#$round))" --argjson runs "$runs" --argjson complete "$complete" \
     --argjson rt "$current_tokens" --argjson ct "$((current_tokens + prior_tokens))" '
  {pr: $pr, url: $url, round: $round,
   identity: {expected_branch: (if $expect == "" then null else $expect end),
              head_branch: $hb},
   range: {base: $base_sha, base_branch: $base, head: $head, exact: "\($base_sha)..\($head)",
           prior_head: (if $prior == "" then null else $prior end), reviewed_from: $from,
           review_scope: $scope},
   runs: $runs, reviewer_complete: $complete,
   round_tokens: $rt, cumulative_tokens: $ct}' > "$round_dir/round.json"
printf '%s\n' "$round_dir"
