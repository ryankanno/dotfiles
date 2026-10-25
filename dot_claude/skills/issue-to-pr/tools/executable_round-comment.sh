#!/usr/bin/env bash
# The round comment the loop reads: a round's comment.md when it is whole
# and scan-clean, else our newest copy of that round's comment on the PR.
# The next round (pr-round.sh) and a refine (pr-refine §1) both read
# through this script, so they cannot disagree on which comment counts.
# The PR read paginates: the gh pr view comments field holds the first
# page only, where a long PR's newest round is not (issue #181).
#
# Interface in:  <owner/repo> <pr> [<round>]
# Interface out: on stdout, round <round>'s comment, or without <round>
#                the comment of the newest round that has one; on stderr,
#                why a comment.md was passed over.
# Exit codes: 0 printed; 1 no usable comment; 2 usage, or an unusable
#             environment (HOME unset, no scan.sh); 5 the gh user or the
#             PR comments could not be read; 127 a dependency is missing.
set -euo pipefail

usage() {
  printf 'usage: round-comment.sh <owner/repo> <pr> [<round>]\n' >&2
  exit 2
}
[[ $# -eq 2 || $# -eq 3 ]] || usage
owner_repo="$1" pr="$2" want="${3:-}"
[[ "$owner_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && "$pr" =~ ^[0-9]+$ ]] || usage
[[ -z "$want" || "$want" =~ ^[0-9]+$ ]] || usage
if [[ -n "$want" ]]; then want=$((10#$want)); fi
if [[ -z "${HOME:-}" ]]; then
  printf 'HOME is not set; the round folder cannot live anywhere\n' >&2
  exit 2
fi
command -v gh >/dev/null || { printf 'gh: not found\n' >&2; exit 127; }
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }

here="$(cd "$(dirname "$0")" && pwd)"
# Deployed trees strip the executable_ prefix; the source repo keeps it.
scan="$here/scan.sh"
[[ -f "$scan" ]] || scan="$here/executable_scan.sh"
[[ -f "$scan" ]] || { printf 'scan.sh not found in %s\n' "$here" >&2; exit 2; }
pd="$HOME/.cache/pr-loop/$owner_repo/pr-$pr"

# A comment.md exists before anyone posts it, so a refine never waits on
# the post. It counts when it has the marker on line 1, its round's
# heading, and the template's footer as its last line, so a file cut off
# anywhere above the footer, or misplaced, cannot stand in for a whole
# one. The shape is checked before the scan, which rewrites the file in
# place. A file that fails the scan was never posted, and the round's
# text leaves the machine through the reviewer.
usable() { # <file> <n>
  local f="$1" n="$2" rc=0
  [[ -r "$f" ]] || { printf 'cannot read %s; using the PR copy of round %s\n' "$f" "$n" >&2; return 1; }
  if [[ "$(head -1 "$f")" != '<!-- pr-loop-comment -->' ]] ||
     ! grep -q "^## Review round $n:" "$f" ||
     [[ "$(tail -n 1 "$f")" != "*Round $n |"* ]]; then
    printf 'not a whole round %s comment: %s; using the PR copy\n' "$n" "$f" >&2
    return 1
  fi
  "$scan" "$f" >/dev/null 2>&1 || rc=$?
  case $rc in
    0) return 0 ;;
    1) printf 'scan hits in %s; using the PR copy of round %s\n' "$f" "$n" >&2 ;;
    *) printf 'scan failed on %s; using the PR copy of round %s\n' "$f" "$n" >&2 ;;
  esac
  return 1
}

# Newest first by number: the glob sorts round-10 before round-2.
disk_n="" disk_file=""
while IFS=$'\t' read -r n f; do
  if usable "$f" "$n"; then disk_n=$n disk_file=$f; break; fi
done < <(for f in "$pd"/round-*/comment.md; do
           [[ -f "$f" ]] || continue
           n="${f%/comment.md}"; n="${n##*/round-}"
           [[ "$n" =~ ^[0-9]+$ ]] || continue
           [[ -z "$want" || $((10#$n)) -eq "$want" ]] || continue
           printf '%s\t%s\n' "$((10#$n))" "$f"
         done | sort -rn)
if [[ -n "$want" && -n "$disk_file" ]]; then cat "$disk_file"; exit 0; fi

# Only this loop's own round comments count: the marker on line 1 and our
# own author, so a marker quoted inside a finding, or anyone who can
# comment on the PR, cannot forge one. One JSON string per line keeps
# each body whole.
me=$(gh api user --jq .login) || {
  printf 'cannot resolve the gh user for the round comments\n' >&2
  exit 5
}
bodies=$(gh api --paginate "repos/$owner_repo/issues/$pr/comments" \
    --jq '.[] | select(.user.login == "'"$me"'") | select(.body | startswith("<!-- pr-loop-comment -->")) | .body | @json') || {
  printf 'cannot read the PR comments\n' >&2
  exit 5
}
# The API lists comments oldest first, and sort_by is stable: the last
# entry is the newest copy of the newest round.
pick=$(jq -cs --arg w "$want" '
  map({n: ((capture("(?m)^## Review round (?<n>[0-9]+):") | .n | tonumber) // null), b: .})
  | map(select(.n != null and ($w == "" or .n == ($w | tonumber))))
  | sort_by(.n) | last // empty' <<<"$bodies")
pr_n=""
if [[ -n "$pick" ]]; then pr_n=$(jq -r .n <<<"$pick"); fi
if [[ -n "$disk_file" ]] && [[ -z "$pr_n" || "$disk_n" -ge "$pr_n" ]]; then
  cat "$disk_file"
elif [[ -n "$pick" ]]; then
  jq -r .b <<<"$pick"
else
  exit 1
fi
