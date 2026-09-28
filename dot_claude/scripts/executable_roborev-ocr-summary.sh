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

# Shared by both passes below: the headings and the range checks number the
# same list, so "call N" names the same call in each.
ocr_calls_def='def ocr_calls: map(select(.type == "tool_use" and .part.tool == "ocr_review") | .part.state);'

# The log is JSONL events followed by the review's plain-text body, so parse
# line by line and skip what is not JSON.
out=$(jq -rRn --arg job "$job" "$ocr_calls_def"'
  def oneline: gsub("\\s*\n\\s*"; " ");
  # A bare </details> in a finding would close the findings container early
  # and hide the findings after it. Only text outside code spans is escaped:
  # GitHub shows an entity inside a span literally, and backticks are the
  # markdown OCR writes. An odd backtick count leaves the last segment outside
  # any span, so it is escaped too.
  def html: split("`") | length as $n | to_entries
    | map(if .key % 2 == 0 or (.key == $n - 1 and $n % 2 == 0)
          then .value | gsub("<"; "&lt;") else .value end)
    | join("`");
  # Paths, tool names and arguments sit in code spans, where GitHub renders
  # "<" as text; only a backtick can end the span early and let a tag through.
  def code: "`" + (tostring | gsub("`"; "")) + "`";
  def paths: map(.path | code) | join(", ");
  # Raw stderr can hold any fence run, so the fence is one tilde longer than
  # the longest run in the text, and never shorter than four.
  def fenced: (if type == "string" then . else tojson end) | .[0:1500] | . as $t | ("~" *(([$t | scan("~+") | length] + [3] | max) + 1)) as $f
    | "\($f)\n\($t)\n\($f)";

  [inputs | fromjson? | objects] as $events
  | if ($events | length) == 0 then
      error("job \($job): no JSON events in the log, so whether ocr_review ran is unknown")
    else . end
  | ($events | ocr_calls) as $calls
  | if ($calls | length) == 0 then
      "### OCR cross-check\n\nJob \($job) made no `ocr_review` call, so this review has no OCR cross-check."
    else
      $calls | to_entries | map(
        .key as $i | .value as $s
        | "### OCR cross-check" + (if ($calls | length) > 1 then " (call \($i + 1) of \($calls | length))" else "" end) + "\n\n"
        + "**Arguments:** \(if $s.input == null then "none recorded" else ($s.input | tojson | code) end)\n\n"
        + if $s.status != "completed" then
            "**Status:** \($s.status | tostring | html)\n\n" + ($s.error // "no error text recorded" | fenced)
          else
            ($s.output | try fromjson catch null) as $o
            | if $o == null then
                "**Status:** completed, but the output is not JSON:\n\n" + ($s.output // "no output recorded" | fenced)
              else
                ($o.manifest.coverage // {}) as $c
                | ($c.failed // []) as $failed
                | ($c.waived // []) as $waived
                | ($o.comments // []) as $findings
                | "- **Status:** \($o.status // "unknown" | html). \($o.message // "No message." | html)\n"
                + "- **Range:** \($o.manifest.input.exact_range // "unknown" | code) (\($o.manifest.input.mode // "unknown mode" | tostring | html))\n"
                + "- **Model:** \($o.llm.provider // "unknown" | tostring | html)/\($o.llm.model // "unknown" | tostring | html), OCR \($o.manifest.execution.ocr_version // "unknown" | tostring | html), \($o.summary.elapsed // "elapsed unknown" | tostring | html)\n"
                + "- **Tool calls:** \($o.tool_calls.total // "unknown") (\($o.tool_calls.failure // "unknown") failed)\n"
                + ([$o.tool_calls.failure_details[]? | "  - \(.tool_name | code) on \(.file_path | code): \(.error // "no error text" | oneline | html)"] | if length > 0 then join("\n") + "\n" else "" end)
                + "\n<details><summary>Files: \($c.selected // [] | length) selected, \($c.completed // [] | length) completed, \($failed | length) failed, \($waived | length) waived, \($c.reused // [] | length) reused</summary>\n\n"
                + ([$o.groups[]? | "- **\(.label | html)**: \(.files | map(code) | join(", "))"] | join("\n"))
                + (if ($failed | length) > 0 then "\n\n**Failed:** \($failed | paths)" else "" end)
                + (if ($waived | length) > 0 then "\n\n**Waived:** \($waived | paths)" else "" end)
                + "\n\n</details>\n\n"
                + "<details><summary>OCR findings: \($findings | length)</summary>\n\n"
                + ([$findings | to_entries[] | .value as $f
                    | "\(.key + 1). **\($f.severity // "unrated" | html)** \("\($f.path // "unknown file"):\($f.start_line // "?")" + (if ($f.end_line // $f.start_line) != $f.start_line then "-\($f.end_line)" else "" end) | code) (\($f.category // "uncategorized" | html)): \($f.content // "no content" | oneline | html)"]
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
# A one-component home (/root) dashes to a bare word that ordinary text holds.
if [[ "$home_dashed" == *-* ]]; then
  out="${out//"$home_dashed"/$tilde}"
fi
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
# A call without input has nothing to compare, but keeps its number.
inputs=$(jq -rRn "$ocr_calls_def"'
  [inputs | fromjson? | objects] | ocr_calls
  | length as $total | to_entries[] | select(.value.input | type == "object")
  | "\(.key + 1)\t\($total)\t\(.value.input | tojson)"' <<<"$log")
while IFS=$'\t' read -r n total input; do
  [ -n "$input" ] || continue
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
  [ "$total" -gt 1 ] && label=" (call $n)"
  if [ "$got" = "$want" ]; then
    printf '\n**Range check%s:** OCR reviewed the same change as the review, %s.\n' "$label" "$(short "$want")"
  else
    printf '\n**Range check%s: mismatch.** OCR reviewed %s, but the review covered %s. OCR'\''s coverage and findings above describe a different change and are no cross-check of this one.\n' "$label" "$(short "$got")" "$(short "$want")"
  fi
done <<<"$inputs"
