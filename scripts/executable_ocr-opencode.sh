#!/usr/bin/env bash
# ocr scan <path>, export review.html, then hand it to opencode.
#   explore -> issue-exploration workflow (verify and file GitHub issues)
#   fix     -> fix the critical/high findings through /issue-to-pr
# Run inside the repository, with <src-path> in that same repository; the
# script refuses any other run before it writes anything. The files go to
# .ocr-opencode/ at the root of the current directory's repository (each
# worktree has its own), and its .gitignore keeps git from tracking them.
# A failed scan leaves no .ocr-opencode/. fix --reuse skips the scan and
# resumes a stopped fix run on the existing review.html.
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

if ! TOP="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "$PWD is not inside a git repository; run it inside the repository" >&2
  exit 2
fi
if [[ $REUSE == 0 ]]; then
  if [[ ! -e $2 ]]; then
    echo "$2 does not exist" >&2
    exit 2
  fi
  # A symlinked file lives in its target's repository, not the link's.
  SRC_DIR="$(realpath "$2")"
  [[ -d $SRC_DIR ]] || SRC_DIR="$(dirname "$SRC_DIR")"
  if [[ "$(git -C "$SRC_DIR" rev-parse --show-toplevel 2>/dev/null)" != "$TOP" ]]; then
    echo "$2 is not inside $TOP; run it inside the repository of $2" >&2
    exit 2
  fi
fi
OUT="$TOP/.ocr-opencode"
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
      PROGRESS="If $OUT/review-progress.md exists, read it first, and skip each bug that it marks as done."
    else
      PROGRESS="Replace any old $OUT/review-progress.md, because review.html is new."
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

[[ $REUSE == 1 ]] || ocr scan --path "$2"
mkdir -p "$OUT"
# review.html holds every finding, security ones too; a git add -A must not
# commit it. --reuse writes it too, for a folder moved from .git/ocr-opencode.
echo '*' >"$OUT/.gitignore"
[[ $REUSE == 1 ]] || ocr session export -o "$REVIEW"
# One line, so the TUI cannot read a newline as Enter and submit early.
exec opencode --prompt "${PROMPT//$'\n'/ }"
