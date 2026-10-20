#!/usr/bin/env bash
# ocr scan <path>, export review.html, then hand it to opencode.
#   explore -> issue-exploration workflow (verify and file GitHub issues)
#   fix     -> fix the critical/high findings through /issue-to-pr
# Run inside the repository. The files go to .git/ocr-opencode/, so git
# never tracks them. fix --reuse skips the scan and resumes a stopped fix
# run on the existing review.html.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") explore <src-path>" >&2
  echo "       $(basename "$0") fix <src-path>" >&2
  echo "       $(basename "$0") fix --reuse" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
REUSE=0
case "$1:$2" in
  fix:--reuse) REUSE=1 ;;
  explore:-*|fix:-*) usage ;;
  explore:*|fix:*) ;;
  *) usage ;;
esac

OUT="$(git rev-parse --path-format=absolute --git-common-dir)/ocr-opencode"
REVIEW="$OUT/review.html"

if [[ $REUSE == 1 && ! -f $REVIEW ]]; then
  echo "no review.html to reuse in $OUT; run fix <src-path> to scan" >&2
  exit 2
fi

case "$1" in
  explore)
    PROMPT="Read $REVIEW.
Find the most critical issues and the architectural issues.
Verify each issue in the code.
File a GitHub issue only for an issue that you verify.
Use your judgment to select the issues to file.
Before you file an issue, search the open and closed issues. Do not file an issue that already exists.
If the gh user does not own the repository, do not file issues. Write each issue draft to $OUT/review-issues.md instead.
Give each issue the labels and details that the repository requires.
Assign each issue that you file to me."
    ;;
  fix)
    if [[ $REUSE == 1 ]]; then
      PROGRESS="If review-progress.md exists, read it first, and skip each bug that it marks as done."
    else
      PROGRESS="Replace any old review-progress.md, because review.html is new."
    fi
    PROMPT="Read $REVIEW, the ocr scan output.
Fix each critical bug and each high bug.
Fix one bug at a time.
Record the progress of each bug in $OUT/review-progress.md.
$PROGRESS
For each bug, verify that the bug is real, because the scan can report bugs that do not exist.
Fix the bug with TDD through /issue-to-pr.
If you use workmux, set the agent to opencode, because the workmux default agent is claude.
Do not run another review, because /issue-to-pr runs the review rounds.
Work autonomously until all bugs are done.
Do not stop to ask for confirmation.
If a step is blocked, record the reason and go to the next step.
Write the final summary to $OUT/review-output.html, then stop."
    ;;
esac

if [[ $REUSE == 0 ]]; then
  mkdir -p "$OUT"
  ocr scan --path "$2"
  ocr session export -o "$REVIEW"
fi
# One line, so the TUI cannot read a newline as Enter and submit early.
exec opencode --prompt "${PROMPT//$'\n'/ }"
