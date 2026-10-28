#!/usr/bin/env bash
# The ocr reviewer binding. The loop's skills call this script, never `ocr`
# directly, so the reviewer stays a swappable slot: a different tool is a
# new directory with the same interface, plus one manifest line.
#
# Interface in: --repo, --out, optional --brief, optional --effort
# (low|medium|high, default medium: the review passes per file group, low
# 1, medium 2, high 3; a pass after the first runs only when the one
# before added a finding), --timeout (minutes, default 80; ocr multiplies
# it by the passes, so the default gives each group 160 minutes),
# --max-tools (tool rounds per group, 50 or more, default 200),
# --concurrency (file groups ocr reviews at once, default 2),
# --max-tokens-budget (tokens per ocr run, not per group, default
# 25000000; a group over it gets one final round and fails as budget,
# and ocr starts no more groups) and --exclude (comma-separated
# gitignore-style globs, merged with rule.json's excludes), and either
# --base/--head (range mode) or --commit (per-commit mode, the
# empty-result retry).
# Interface out: <out>/review.json (the tool's own output), stdout.txt,
# stderr.txt, cmd.txt (the exact invocation, for the report), session.txt
# (session id, for resume and round-over-round compare; also on a failure
# when review.json holds one), exit.txt on failure.
set -euo pipefail

usage() {
  printf 'usage: review.sh --repo <dir> --out <dir> [--brief <file>] [--effort low|medium|high] [--timeout <minutes>] [--max-tools <n>] [--max-tokens-budget <n>] [--concurrency <n>] [--exclude <globs>] (--base <ref> --head <ref> | --commit <sha>)\n' >&2
  exit 2
}

repo="" out="" brief="" base="" head="" commit="" effort="medium" timeout="80" max_tools="200" budget="25000000" concurrency="2" exclude=""
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
    --effort) [[ $# -ge 2 ]] || usage; effort="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || usage; timeout="$2"; shift 2 ;;
    --max-tools) [[ $# -ge 2 ]] || usage; max_tools="$2"; shift 2 ;;
    --max-tokens-budget) [[ $# -ge 2 ]] || usage; budget="$2"; shift 2 ;;
    --concurrency) [[ $# -ge 2 ]] || usage; concurrency="$2"; shift 2 ;;
    --exclude) [[ $# -ge 2 ]] || usage; exclude="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$repo" && -n "$out" && -d "$repo" ]] || usage
case "$effort" in low|medium|high) ;; *) usage ;; esac
# ocr reads 0 as no deadline (or no budget) and a leading zero as octal
# (080 fails); its own floor for the tool cap is 50.
[[ "$timeout" =~ ^[1-9][0-9]*$ ]] || usage
# The digit caps keep a value inside bash and ocr integers; a longer one
# wraps in bash arithmetic and slips past the floor.
[[ "$max_tools" =~ ^[1-9][0-9]{0,8}$ ]] && (( max_tools >= 50 )) || usage
[[ "$budget" =~ ^[1-9][0-9]{0,17}$ ]] || usage
[[ "$concurrency" =~ ^[1-9][0-9]{0,8}$ ]] || usage
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
# files. A third stop is ocr's own context limit: "Context compression
# exceeded threshold for <group>, stopping." ended a group of a
# 6,475-line script and its 5,775-line test after 111 tool calls, with
# no review of either (issue #165). No setting below acts on it, and
# render.sh names it as each failed file's reason.
# The model provider serves 6 requests at once and queues the
# rest, so ocr's default 8 parallel groups wait out the 15-minute task
# timeout. Loops that run at the same time share those 6, so the default
# is 2 groups, not 6; one group at a time (issue #42) ran a 3-group round
# for 3h52m (issue #186). The cap is the provider's, not ocr's, so the
# code does not enforce it. The task deadline is --timeout times
# the review rounds (ocr multiplies them), so the default 80 gives each
# group 160 minutes at the default medium.
# Effort sets only the review rounds per group (high 3, medium 2); a
# round after the first runs only when the one before added a finding,
# and its turns reason longest (issue #52: round 2 of a 7-file group ran
# 28 requests, many at 12k to 32k reasoning tokens each).
# At 100 tool rounds, 3 of the 73 rounds run under that cap ended partial
# with files failed on it, so the default is 200. The token budget caps
# the whole ocr run, not one group: a stalled 7-file round used 6.3M, below
# two complete rounds (12.95M and 7.76M), so no budget stops a stall without
# cutting complete rounds. The default 25M is about twice the largest
# complete round, room for the higher tool cap and the test files; it would
# have cut no past round (the highest, a partial one, used 17.9M).
# rule.json replaces ocr's default path filter for test files and
# Markdown only, so the reviewer reads the tests a PR adds and a
# Markdown-only PR gets a review (issue #108). Lockfiles, generated code, build
# output and vendored code stay excluded, as a tool or a third party writes
# them; test data stays excluded too, as it holds no logic to review. Its
# exclude list repeats ocr's test-data globs, since an include re-admits
# anything it matches and only an exclude wins over it.
# --rule also replaces a repo's own .opencodereview/rule.json.
rule="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rule.json"
[[ -f "$rule" ]] || { printf 'rule.json not found: %s\n' "$rule" >&2; exit 2; }
args=(review --format json --output "$out/review.json"
      --concurrency "$concurrency" --max-tools "$max_tools" --max-tokens-budget "$budget"
      --timeout "$timeout" --effort "$effort" --rule "$rule")
if [[ -n "$brief" ]]; then
  [[ -f "$brief" ]] || { printf 'brief not found: %s\n' "$brief" >&2; exit 2; }
  args+=(--background-file "$brief")
fi
if [[ -n "$exclude" ]]; then args+=(--exclude "$exclude"); fi
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
  printf '%s\n' "$rc" >"$out/exit.txt" 2>/dev/null || true
  # ocr can fail after it wrote a whole review.json (PR #162: "no space
  # left on device" on its session_end write); the run is still that session.
  # The disk can still be full, so a failed write must not replace ocr's code.
  sid=$(jq -r '.session_id // empty' "$out/review.json" 2>/dev/null || true)
  if [[ -n "$sid" ]]; then printf '%s\n' "$sid" >"$out/session.txt" 2>/dev/null || true; fi
  exit "$rc"
fi

# The session id ships inside the tool's own output; recording it here keeps
# the skills from re-parsing the json.
jq -r '.session_id // empty' "$out/review.json" >"$out/session.txt" 2>/dev/null || true
