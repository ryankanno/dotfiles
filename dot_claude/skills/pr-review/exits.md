# pr-round.sh exits

pr-review §1 links here when `pr-round.sh` exits other than 0 or 7.
In the issue-to-pr loop, the pane acts by the exit-code table in the
dispatch template's "Review rounds" section instead.

## Exit 2

Exit 2 is a usage error, an unusable environment, a
`refine-dispositions.md` that fails the scan (pr-review §1), or a brief
over the background limit. Its stderr line names which.

A brief over the limit on its own, or one whose assembled background
overflows once the standing dispositions join it, stops the round with
exit 2 before any review runs, leaving the round dir untouched:
condense it to the task (its asks, the settled decisions, the
constraints) and rerun, never pass a dispatch prompt or loop
instructions as the brief. In the issue-to-pr loop, the pane stops
instead: the brief is the orchestrator's to condense. A convergence
round runs no reviewer, so it writes no `background.md` and checks no
limit.

## Exits 4, 5, 6, 8 and 127

When GitHub never reports the `--expect-head` SHA, the script exits 8
before it creates or changes any round evidence: run the round again
once.

The script exits 4 when the PR is missing, not open, or not
resolvable, 5 when the repository, its refs, the changed-file
listing, the gh user, or the PR comments cannot be read, and 127 when
`gh`, `jq`, or `git` is
missing. It exits 6 when the round directory already holds evidence:
`--rerun` moves that evidence into a `superseded-*/` subdirectory, then
runs the round. Pass `--rerun` only when the earlier run of this round
died and left no `round.json` (a harness timeout kills it), or when pr-review §2
sends a convergence round back to the reviewer. A round dir with a
`round.json` and a usable comment (below) is a finished round: use it.

## Exit 9: an earlier round has no comment

The script exits 9 before any review when an earlier round in the PR's
round folder has a `round.json` and no usable comment. A usable comment
is a whole, scan-clean `comment.md` in that round's directory, or a
round comment of yours on the PR with that round's heading. A round
whose `round.json` is under `superseded-*/` does not count. The stderr
line names the round, and the round dir holds no evidence. In the
issue-to-pr loop, the pane stops with
`blocked: round <N> has no comment`.
