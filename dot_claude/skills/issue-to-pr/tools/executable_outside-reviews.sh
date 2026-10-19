#!/usr/bin/env bash
# The PR's reviews from outside the loop (a review bot, a colleague, you):
# top-level comments, inline comments and review bodies, from the
# manifest's outside_reviewers allowlist plus the gh user. Anyone who can
# comment on a PR can write text that reaches the refine, so an author off
# the allowlist never counts. The loop's own round comments are not outside
# reviews.
#
# Interface in:  --slug <owner/repo> --pr <n> [--seen <pr-dir> [--before <N>]]
#                --seen drops every item a round-*/outside.json under
#                <pr-dir> already recorded; --before limits that to rounds
#                before N, so a rerun of a round sees what it saw before.
# Interface out: a JSON array on stdout, oldest first per kind, of
#                {id, kind, login, path, line, body, url}; id is
#                "<kind>:<github id>", kind is issue_comment, inline or
#                review; path and line are null except on inline comments.
# Exit codes: 0 listed; 2 usage; 5 a GitHub read failed; 127 a dependency
# is missing.
set -euo pipefail

usage() {
  printf 'usage: outside-reviews.sh --slug <owner/repo> --pr <n> [--seen <pr-dir> [--before <N>]]\n' >&2
  exit 2
}

slug="" pr="" seen="" before=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) [[ $# -ge 2 ]] || usage; slug="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || usage; pr="$2"; shift 2 ;;
    --seen) [[ $# -ge 2 ]] || usage; seen="$2"; shift 2 ;;
    --before) [[ $# -ge 2 ]] || usage; before="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$slug" && -n "$pr" ]] || usage
[[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || usage
[[ "$pr" =~ ^[0-9]+$ ]] || usage
[[ -z "$before" || "$before" =~ ^[0-9]+$ ]] || usage
command -v gh >/dev/null || { printf 'gh: not found\n' >&2; exit 127; }
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }

here="$(cd "$(dirname "$0")" && pwd)"
allow=$(jq -c '.outside_reviewers // [] | if type == "array" and all(type == "string" and test("^\\S+$")) then . else error end' "$here/manifest.json") || {
  printf 'cannot read the manifest: %s\n' "$here/manifest.json" >&2
  exit 2
}
me=$(gh api user --jq .login) || { printf 'cannot resolve the gh user\n' >&2; exit 5; }
# GitHub logins are case-insensitive, and the allowlist is typed by hand.
allow=$(jq -c --arg me "$me" '. + [$me] | map(ascii_downcase) | unique' <<<"$allow")

# --paginate prints one array per page; slurping and adding joins them. A
# failed read exits 5: an empty list would read as "no outside reviews".
fetch() { # endpoint -> one JSON array
  local raw
  raw=$(gh api --paginate "repos/$slug/$1") || { printf 'cannot read %s\n' "$1" >&2; exit 5; }
  jq -cs 'add // []' <<<"$raw" || { printf 'cannot parse %s\n' "$1" >&2; exit 5; }
}
issue=$(fetch "issues/$pr/comments")
inline=$(fetch "pulls/$pr/comments")
reviews=$(fetch "pulls/$pr/reviews")

seen_ids='[]'
if [[ -n "$seen" ]]; then
  for f in "$seen"/round-*/outside.json; do
    [[ -f "$f" ]] || continue
    n="${f%/outside.json}"; n="${n##*/round-}"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if [[ -n "$before" && $((10#$n)) -ge $((10#$before)) ]]; then continue; fi
    next=$(jq -c --argjson s "$seen_ids" '$s + [.[].id]' "$f" 2>/dev/null) || {
      printf 'cannot read %s; its items count as unseen\n' "$f" >&2
      continue
    }
    seen_ids=$next
  done
fi

# The PR's comments ride on stdin, never in an argument: on a long PR they
# outgrow the exec argument limit.
printf '%s\n%s\n%s\n' "$issue" "$inline" "$reviews" | jq -s --argjson allow "$allow" --argjson seen "$seen_ids" '
  def item($kind): {id: "\($kind):\(.id)", kind: $kind, login: .user.login,
                    path: (.path // null), line: (.line // .original_line // null),
                    body: .body, url: (.html_url // null)};
  [(.[0][] | item("issue_comment")), (.[1][] | item("inline")), (.[2][] | item("review"))]
  | map(select(.login != null and ((.login | ascii_downcase) as $l | $allow | index($l))))
  | map(select((.body // "") | length > 0))
  | map(select(.body | startswith("<!-- pr-loop-comment -->") | not))
  | map(select(.id as $i | $seen | index($i) | not))'
