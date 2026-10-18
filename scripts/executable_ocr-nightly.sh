#!/usr/bin/env bash
# Nightly review: ocr scan <path>, export review.html, then hand it to opencode.
#   explore -> issue-exploration workflow (verify and file GitHub issues)
#   fix     -> fix the critical/high findings in a worktree
# Run from the repository root.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <explore|fix> <src-path>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage

case "$1" in
  explore)
    PROMPT="Read review.html.
Find the most critical issues and the architectural issues.
Verify each issue in the code.
File a GitHub issue only for an issue that you verify.
Use your judgment to select the issues to file.
Give each issue the labels and details that the repository requires."
    ;;
  fix)
    PROMPT="Make a new worktree named fix/review-critical-highs.
If you use workmux, set the agent to opencode, because the workmux default agent is claude.
Read review.html, the ocr scan output.
Fix each critical bug and each high bug.
Fix one bug at a time.
For each bug, do these steps:
1. Verify that the bug is real, because the scan can report bugs that do not exist.
2. Fix the bug with TDD through /issue-to-pr.
3. Run /pr-review on the PR.
4. Run a quick adversarial review of the fix.
Work autonomously until all bugs are done.
Do not stop to ask for confirmation.
If a step is blocked, record the reason and go to the next step.
Write the final summary to review_output.html, then stop."
    ;;
  *) usage ;;
esac

ocr scan --path "$2"
ocr session export -o review.html
# One line, so the TUI cannot read a newline as Enter and submit early.
exec opencode --prompt "${PROMPT//$'\n'/ }"
