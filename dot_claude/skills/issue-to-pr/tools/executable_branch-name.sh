#!/usr/bin/env bash
# The loop's deterministic branch name. Idempotency rests on a rerun
# computing the same name, so the rule lives in tested code rather than in
# prose an agent re-derives with its own whitespace and slug choices.
#
# Interface in:  --type gh|md|html --locator <source locator> --title <title>,
#                the item text on stdin.
# Interface out: loop/<type>-<slug>-<hash8> on stdout. <slug> is the title
#                lowercased, non-alphanumeric runs as one hyphen, capped at 40
#                characters, "task" when empty. <hash8> is the first 8 hex of
#                sha256 over the locator, a newline, then the item text with
#                trailing newlines stripped.
# Exit codes: 0 printed; 2 usage; 127 no sha256 tool.
set -euo pipefail

usage() {
  printf 'usage: branch-name.sh --type gh|md|html --locator <locator> --title <title> < item-text\n' >&2
  exit 2
}

type="" locator="" title=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) [[ $# -ge 2 ]] || usage; type="$2"; shift 2 ;;
    --locator) [[ $# -ge 2 ]] || usage; locator="$2"; shift 2 ;;
    --title) [[ $# -ge 2 ]] || usage; title="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$type" in gh|md|html) ;; *) usage ;; esac
[[ -n "$locator" ]] || usage

if command -v sha256sum >/dev/null; then sha=(sha256sum)
elif command -v shasum >/dev/null; then sha=(shasum -a 256)
else printf 'sha256sum or shasum: not found\n' >&2; exit 127
fi

text="$(cat)"
hash=$(printf '%s\n%s' "$locator" "$text" | "${sha[@]}" | cut -c1-8)

slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
slug="${slug#-}"
slug="${slug:0:40}"
while [[ "$slug" == *- ]]; do slug="${slug%-}"; done
[[ -n "$slug" ]] || slug=task

printf 'loop/%s-%s-%s\n' "$type" "$slug" "$hash"
