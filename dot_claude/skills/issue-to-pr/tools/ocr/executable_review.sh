#!/usr/bin/env bash
# The ocr reviewer binding. The loop's skills call this script, never `ocr`
# directly, so the reviewer stays a swappable slot: a different tool is a
# new directory with the same interface, plus one manifest line.
#
# Interface in: --repo, --out, optional --brief, and either --base/--head
# (range mode) or --commit (per-commit mode, the empty-result retry).
# Interface out: <out>/review.json (the tool's own output), stdout.txt,
# stderr.txt, cmd.txt (the exact invocation, for the report), session.txt
# (session id, for resume and round-over-round compare), exit.txt on failure.
set -euo pipefail

usage() {
  printf 'usage: review.sh --repo <dir> --out <dir> [--brief <file>] (--base <ref> --head <ref> | --commit <sha>)\n' >&2
  exit 2
}

repo="" out="" brief="" base="" head="" commit=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    # The value guards keep a missing option value a usage error (exit 2)
    # rather than a set -u abort (exit 1).
    --repo) [[ $# -ge 2 ]] || usage; repo="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || usage; out="$2"; shift 2 ;;
    --brief) [[ $# -ge 2 ]] || usage; brief="$2"; shift 2 ;;
    --base) [[ $# -ge 2 ]] || usage; base="$2"; shift 2 ;;
    --head) [[ $# -ge 2 ]] || usage; head="$2"; shift 2 ;;
    --commit) [[ $# -ge 2 ]] || usage; commit="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$repo" && -n "$out" && -d "$repo" ]] || usage
# The wrapper cds into the repo before invoking the tool, so relative
# output and brief paths would resolve against the wrong directory.
case "$out" in /*) ;; *) printf 'out must be an absolute path\n' >&2; exit 2 ;; esac
if [[ -n "$brief" ]]; then
  case "$brief" in /*) ;; *) printf 'brief must be an absolute path\n' >&2; exit 2 ;; esac
fi
if [[ -n "$commit" ]]; then
  [[ -z "$base$head" ]] || usage
  mode=commit
elif [[ -n "$base" && -n "$head" ]]; then
  mode=range
else
  usage
fi

command -v ocr >/dev/null || { printf 'ocr: not found\n' >&2; exit 127; }
command -v jq >/dev/null || { printf 'jq: not found\n' >&2; exit 127; }
mkdir -p "$out"

# Partial runs failed on ocr's own caps, not on the code: "reached the
# maximum tool-request rounds" and "file review exceeded its time limit",
# a 26-line file among them, and a full re-review re-failed the same
# files. The model provider serves 6 requests at once and queues the
# rest, so the default 8 parallel groups wait out the 15-minute task
# timeout. These are roborev's settings (review_guidelines in its
# config), the loop that converged: one group at a time, room for 100
# tool rounds and 80 minutes per task.
args=(review --format json --output "$out/review.json"
      --concurrency 1 --max-tools 100 --timeout 80 --effort high)
if [[ -n "$brief" ]]; then
  [[ -f "$brief" ]] || { printf 'brief not found: %s\n' "$brief" >&2; exit 2; }
  args+=(--background-file "$brief")
fi
if [[ "$mode" == commit ]]; then
  args+=(--commit "$commit")
else
  args+=(--from "$base" --to "$head")
fi

# The audit record quotes each argument (%q), so a copied line reproduces
# the real argv even when a path carries spaces.
printf 'ocr' >"$out/cmd.txt"
printf ' %q' "${args[@]}" >>"$out/cmd.txt"
printf '\n' >>"$out/cmd.txt"
cd "$repo"
set +e
ocr "${args[@]}" >"$out/stdout.txt" 2>"$out/stderr.txt"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  printf '%s\n' "$rc" >"$out/exit.txt"
  exit "$rc"
fi

# The session id ships inside the tool's own output; recording it here keeps
# the skills from re-parsing the json.
jq -r '.session_id // empty' "$out/review.json" >"$out/session.txt" 2>/dev/null || true
