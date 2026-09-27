#!/usr/bin/env bash
# Render the ocr_review call(s) recorded in a roborev job log as a Markdown
# section for a PR comment. The log is the only place the OCR JSON survives:
# roborev's stored review keeps the agent's prose, not the tool output.
#
# Usage: roborev-ocr-summary.sh <job_id>
set -euo pipefail

job="${1:?usage: roborev-ocr-summary.sh <job_id>}"
# OCR names its session directories after the repo path with / turned into -,
# e.g. Users-alice-Projects-foo, so the home directory appears in that form too.
home_dashed="${HOME#/}"
home_dashed="${home_dashed//\//-}"

# Captured rather than piped: a failed read must stop here, not reach jq as an
# empty log that reads like a review which never called ocr_review.
log=$(roborev log --raw "$job")

# The log is JSONL events followed by the review's plain-text body, so parse
# line by line and skip what is not JSON.
out=$(jq -rRn --arg job "$job" '
  def oneline: gsub("\\s*\n\\s*"; " ");
  # A bare </details> in a finding would close the findings container early
  # and hide the findings after it. Only text outside code spans is escaped:
  # GitHub shows an entity inside a span literally, and backticks are the
  # markdown OCR writes.
  def html: split("`") | to_entries
    | map(if .key % 2 == 0 then .value | gsub("<"; "&lt;") else .value end)
    | join("`");
  def paths: map("`\(.path)`") | join(", ");

  [inputs | fromjson? | objects] as $events
  | if ($events | length) == 0 then
      error("job \($job): no JSON events in the log, so whether ocr_review ran is unknown")
    else . end
  | [$events[] | select(.type == "tool_use" and .part.tool == "ocr_review") | .part.state] as $calls
  | if ($calls | length) == 0 then
      "### OCR cross-check\n\nJob \($job) made no `ocr_review` call, so this review has no OCR cross-check."
    else
      $calls | to_entries | map(
        .key as $i | .value as $s
        | "### OCR cross-check" + (if ($calls | length) > 1 then " (call \($i + 1) of \($calls | length))" else "" end) + "\n\n"
        + "**Arguments:** `\($s.input | tojson)`\n\n"
        + if $s.status != "completed" then
            "**Status:** \($s.status)\n\n```\n\($s.error // "no error text recorded" | .[0:1500])\n```"
          else
            ($s.output | try fromjson catch null) as $o
            | if $o == null then
                "**Status:** completed, but the output is not JSON:\n\n```\n\($s.output | .[0:1500])\n```"
              else
                ($o.manifest.coverage // {}) as $c
                | ($c.failed // []) as $failed
                | ($c.waived // []) as $waived
                | ($o.comments // []) as $findings
                | "- **Status:** \($o.status). \($o.message)\n"
                + "- **Range:** `\($o.manifest.input.exact_range // "unknown")` (\($o.manifest.input.mode // "unknown mode"))\n"
                + "- **Model:** \($o.llm.provider // "unknown")/\($o.llm.model // "unknown"), OCR \($o.manifest.execution.ocr_version // "unknown"), \($o.summary.elapsed // "elapsed unknown")\n"
                + "- **Tool calls:** \($o.tool_calls.total // "unknown") (\($o.tool_calls.failure // "unknown") failed)\n"
                + ([$o.tool_calls.failure_details[]? | "  - `\(.tool_name)` on `\(.file_path)`: \(.error // "no error text" | oneline)"] | if length > 0 then join("\n") + "\n" else "" end)
                + "\n<details><summary>Files: \($c.selected // [] | length) selected, \($c.completed // [] | length) completed, \($failed | length) failed, \($waived | length) waived, \($c.reused // [] | length) reused</summary>\n\n"
                + ([$o.groups[]? | "- **\(.label | html)**: \(.files | map("`\(.)`") | join(", "))"] | join("\n"))
                + (if ($failed | length) > 0 then "\n\n**Failed:** \($failed | paths)" else "" end)
                + (if ($waived | length) > 0 then "\n\n**Waived:** \($waived | paths)" else "" end)
                + "\n\n</details>\n\n"
                + "<details><summary>OCR findings: \($findings | length)</summary>\n\n"
                + ([$findings | to_entries[] | .value as $f
                    | "\(.key + 1). **\($f.severity)** `\($f.path):\($f.start_line)" + (if $f.end_line != $f.start_line then "-\($f.end_line)" else "" end) + "` (\($f.category)): \($f.content // "no content" | oneline | html)"]
                   | if length > 0 then join("\n") else "None." end)
                + "\n\n</details>"
              end
          end
      ) | join("\n\n")
    end
' <<<"$log")
# OCR error text is raw stderr and names local paths (session files, worktrees),
# and the output goes on a PR. Literal replacement, not sed: a home path is not
# a regex, and one holding a metacharacter would break the pattern.
tilde='~'
out="${out//"$HOME"/$tilde}"
out="${out//"$home_dashed"/$tilde}"
printf '%s\n' "$out"

# Whether each ocr_review call reviewed the change the job did. The review
# agent picks from/to itself, and the prompt names no base: a guess taken from
# a SHA in its Previous Reviews block has handed OCR a diff many times the size
# of the change. OCR's coverage and findings then describe that other change,
# and nothing above says so.
job_json=$(roborev show --job "$job" --json)
git_ref=$(jq -r '.job.git_ref // ""' <<<"$job_json")
repo=$(jq -r '.job.repo_path // "."' <<<"$job_json")
full() { git -C "$repo" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null || printf '%s' "$1"; }
short() { sed -E 's/([0-9a-f]{7})[0-9a-f]{33}/\1/g' <<<"$1"; }
case "$git_ref" in
  *..*) want="range $(full "${git_ref%%..*}")..$(full "${git_ref##*..}")" ;;
  dirty | "") want="uncommitted changes" ;;
  *) want="commit $(full "$git_ref")" ;;
esac
inputs=$(jq -cRn '
  inputs | fromjson? | objects | select(.type == "tool_use" and .part.tool == "ocr_review") | .part.state.input' <<<"$log")
count=$(grep -c . <<<"$inputs" || true)
n=0
while IFS= read -r input; do
  [ -n "$input" ] || continue
  n=$((n + 1))
  commit=$(jq -r '.commit // empty' <<<"$input")
  from=$(jq -r '.from // empty' <<<"$input")
  to=$(jq -r '.to // empty' <<<"$input")
  if [ -n "$commit" ]; then
    got="commit $(full "$commit")"
  elif [ -n "$from$to" ]; then
    got="range $(full "$from")..$(full "$to")"
  else
    got="uncommitted changes"
  fi
  label=""
  [ "$count" -gt 1 ] && label=" (call $n)"
  if [ "$got" = "$want" ]; then
    printf '\n**Range check%s:** OCR reviewed the same change as the review, %s.\n' "$label" "$(short "$want")"
  else
    printf '\n**Range check%s: mismatch.** OCR reviewed %s, but the review covered %s. OCR'\''s coverage and findings above describe a different change and are no cross-check of this one.\n' "$label" "$(short "$got")" "$(short "$want")"
  fi
done <<<"$inputs"
