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

# The log is JSONL events followed by the review's plain-text body, so parse
# line by line and skip what is not JSON.
roborev log --raw "$job" | jq -rRn --arg job "$job" '
  def oneline: gsub("\\s*\n\\s*"; " ");
  def paths: map("`\(.path)`") | join(", ");

  [inputs | fromjson? | select(.type == "tool_use" and .part.tool == "ocr_review") | .part.state] as $calls
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
                + "- **Model:** \($o.llm.provider)/\($o.llm.model), OCR \($o.manifest.execution.ocr_version // "unknown"), \($o.summary.elapsed)\n"
                + "- **Tool calls:** \($o.tool_calls.total) (\($o.tool_calls.failure) failed)\n"
                + ([$o.tool_calls.failure_details[]? | "  - `\(.tool_name)` on `\(.file_path)`: \(.error | oneline)"] | if length > 0 then join("\n") + "\n" else "" end)
                + "\n<details><summary>Files: \($c.selected // [] | length) selected, \($c.completed // [] | length) completed, \($failed | length) failed, \($waived | length) waived, \($c.reused // [] | length) reused</summary>\n\n"
                + ([$o.groups[]? | "- **\(.label)**: \(.files | map("`\(.)`") | join(", "))"] | join("\n"))
                + (if ($failed | length) > 0 then "\n\n**Failed:** \($failed | paths)" else "" end)
                + (if ($waived | length) > 0 then "\n\n**Waived:** \($waived | paths)" else "" end)
                + "\n\n</details>\n\n"
                + "<details><summary>OCR findings: \($findings | length)</summary>\n\n"
                + ([$findings | to_entries[] | .value as $f
                    | "\(.key + 1). **\($f.severity)** `\($f.path):\($f.start_line)" + (if $f.end_line != $f.start_line then "-\($f.end_line)" else "" end) + "` (\($f.category)): \($f.content | oneline)"]
                   | if length > 0 then join("\n") else "None." end)
                + "\n\n</details>"
              end
          end
      ) | join("\n\n")
    end
' | sed -e "s#${HOME}#~#g" -e "s#${home_dashed}#~#g"
# OCR error text is raw stderr and names local paths (session files, worktrees);
# the output goes on a PR, so the home directory never leaves the machine.
