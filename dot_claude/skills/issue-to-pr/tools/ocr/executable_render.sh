#!/usr/bin/env bash
# The ocr reviewer binding's renderer: turns the tool's review.json into the
# reviewer sections of a PR comment. The coupling to ocr's output shape lives
# here, with the binding, so a reviewer swap never touches the skills.
#
# Output is fact-only: every line comes from the json, nothing is inferred.
# The status line is printed verbatim whether the run completed or not; the
# skill reading this output decides what an incomplete run means.
set -euo pipefail

dir="${1:-}"
[[ -n "$dir" ]] || {
  printf 'usage: render.sh <dir containing review.json>\n' >&2
  exit 2
}
if [[ -d "$dir" && ! -f "$dir/review.json" ]]; then
  # A failed binding run leaves a directory but no review.json (ocr failed
  # or is missing); the run still renders, as the gap it is, so a reviewer
  # section never goes missing from a round comment.
  printf -- '- **Status:** `missing`. The run produced no review output.\n'
  exit 0
fi
[[ -f "$dir/review.json" ]] || {
  printf 'usage: render.sh <dir containing review.json>\n' >&2
  exit 2
}

# The jq can still fail on a review.json that exists but does not parse
# (a truncated mid-write from a failing reviewer); the run must render as
# the gap it is, never abort with no reviewer section at all.
out="$(jq -r '
  def obj: if type == "object" then . else {} end;
  def arr: if type == "array" then . else [] end;
  def text: if type == "string" then . elif type == "null" then "unknown" else tojson end;
  def oneline: text | gsub("\\s*\n\\s*"; " ");
  def code: text | gsub("`"; "") | "`" + . + "`";
  # Tag names are case-insensitive in HTML and tolerate inner whitespace, and
  # an opening tag breaks the collapsed block as surely as a closing one, so
  # every details tag is entity-escaped whatever its form.
  def safe: gsub("(?i)</[[:space:]]*details[[:space:]]*>"; "&lt;/details&gt;")
    | gsub("(?i)<details([[:space:]][^>]*)?>"; "&lt;details&gt;");
  # The fence must be longer than any tilde run inside the text, and never
  # shorter than three, or the block closes early.
  def fenced: text | . as $t
    | ("~" * (([$t | scan("~+") | length] + [3] | max) + 1)) as $f
    | "\($f)\n\($t)\n\($f)";

  # The llm identity stays in review.json on disk; PR comments never
  # publish the provider or model the loop runs on.
  (.summary | obj) as $s
  | (.tool_calls | obj) as $tc
  | (($tc.by_tool) | obj) as $bt
  | (.comments | arr) as $cs
  | ((.manifest | obj).input | obj) as $in
  | ((.manifest | obj).execution | obj) as $ex
  | ((.manifest | obj).coverage | obj) as $cov
  | "- **Reviewer:** OpenCodeReview \($ex.ocr_version // "unknown" | code).\n"
  + "- **Status:** \(.status // "unknown" | code). \(.message // "No message." | text | safe | oneline)\n"
  + "- **Range:** \($in.exact_range // "unknown" | code) (mode \($in.mode // "unknown" | code)), resolved by the orchestrator from the PR.\n"
  + (if ($s.total_tokens == null) then "- **Tokens:** unknown\n"
     else "- **Tokens:** \($s.total_tokens) total (\($s.input_tokens // "unknown") input, \($s.output_tokens // "unknown") output, \($s.cache_read_tokens // "none") cache read), elapsed \($s.elapsed // "unknown").\n" end)
  + "- **Tool calls:** \($tc.total // "unknown") (\($tc.failure // "unknown") failed)"
  + (if ($bt | length) > 0
     then ": " + ($bt | to_entries | sort_by(.key) | map("\(.key | code) \(.value)") | join(", "))
     else "" end) + "\n"
  + "- **Files:** \(($cov.selected | arr) | length) selected, \(($cov.completed | arr) | length) completed, \(($cov.failed | arr) | length) failed, \(($cov.waived | arr) | length) waived, \(($cov.reused | arr) | length) reused.\n"
  + (if (($cov.failed | arr) | length) > 0 then
       "- **Failed files:** \(($cov.failed | arr) | map((.path // "?") | text | safe) | join(", "))\n"
     else "" end)
  + (if ($cs | length) == 0 then
       "- **Findings:** none.\n"
     else
       "- **Findings:**\n"
        + ([$cs | to_entries[]
            | "- \(.key + 1). **\(.value.category // "uncategorized" | text | safe)/\(.value.severity // "unknown" | text | safe)** \(.value.path // "unknown file" | text | safe | code):\(.value.start_line // "?")-\(.value.end_line // .value.start_line // "?"): \(.value.content | text | safe | oneline)"
         + (if (.value.suggestion_code // null) != null then
             # Every line of the fenced block carries the list indent;
             # content or a closing fence at column 0 ends the list item
             # and leaves a fence open that swallows the rest of the
             # comment.
             "\n\n" + ((.value.suggestion_code | text | safe | fenced)
                        | split("\n") | map("  " + .) | join("\n"))
           else "" end)]
         | join("\n")) + "\n"
     end)
  + "- **Session:** \(.session_id // "unknown" | code)"
' "$dir/review.json" 2>/dev/null)" || {
  printf -- '- **Status:** `unparseable`. The run left review output that does not parse.\n'
  exit 0
}
printf '%s\n' "$out"
