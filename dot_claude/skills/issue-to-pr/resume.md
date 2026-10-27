# Resuming a PR

issue-to-pr §2 and its pane-death policy link here when an open PR
already exists on the loop's branch.

If no pane runs on the worktree,
reopen it with `workmux open <handle>` and the dispatch prompt from
[`dispatch-prompt-template.md`](dispatch-prompt-template.md), with its
"Resuming" section filled in: never a re-entry text of your own. Fill
its refine-round count and its convergence flag from what this prints:

```bash
$HOME/.claude/skills/issue-to-pr/tools/resume-state.sh <owner/repo> <n>
```

`refine_rounds` is the count, and `newest_finished` is the kind of the
newest finished round. When it exits 1 (the PR has no `rounds.txt`) or
fails, use the template's unknown-count bullet and leave out its
convergence-flag bullet. If the
prior run left
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md`, read it and
carry its verdict forward into the resume: a capped-unrecovered resume
inherits the remaining findings instead of rediscovering them, and a
blocked resume inherits its reason.
