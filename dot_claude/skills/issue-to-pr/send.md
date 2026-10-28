# Instructions to a stopped pane

issue-to-pr §6 links here when it sends the pane an instruction after
the pane stops.

## A refine instruction

A disposition does not hold, and refine rounds remain.
Before you send a refine instruction, check that the PR is `OPEN`
(`gh pr view <n> --json state -q .state`). When it is not, send
nothing, and the loop ends `blocked` with the reason "PR <n> is
<state>".

```bash
workmux send <handle> "Refine round <k> on PR <n>: the orchestrator overrules <finding>: <reason>. Run the pr-refine skill on it, then the convergence round."
```

`<k>` is the `refine_rounds` that
`$HOME/.claude/skills/issue-to-pr/tools/resume-state.sh <owner/repo> <n>`
prints, plus 1. On exit 2, fix the call or the environment and run it
once more. On a second exit 2, or any other non-zero exit, send
nothing: the loop ends `blocked` with the script's stderr line. Add
nothing to the instruction beyond the finding and the reason: no fix
directions and no retry policy. `workmux send` prints nothing when it
succeeds. Verify the delivery with `workmux capture <handle>`, and
send again only when the capture does not show the instruction.

## A convergence instruction after a conflict stop

The pane stopped on `blocked: PR <n> conflicts with <base>`.
The loop ends `blocked`, and the PR stays a draft. A later run resumes
the loop after the human merges the base. It reads
`gh pr view <n> --json state,mergeStateStatus,headRefOid`. It sends
the instruction only when the PR is `OPEN` and its
`mergeStateStatus` is not `DIRTY`. Otherwise it sends nothing, and
the loop stays `blocked`. Send it
with `<new headRefOid>` from that read, and verify the delivery as
for a refine instruction. When a resume reopens the pane, put the
instruction in its dispatch prompt's "Resuming" section instead of a
send.

```bash
workmux send <handle> "Convergence round on PR <n>: the base is merged at <new headRefOid>. Run the convergence round at this head."
```
