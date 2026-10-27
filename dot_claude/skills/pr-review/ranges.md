# Review ranges

How `pr-round.sh` picks a round's range, and what `round.json` records
for it. The script computes all of it, and `finding-scope.sh`
classifies each finding against it. pr-review §1 links here.

## The delta

From round 2 on, `round.json` carries `range.prior_head` (the previous
round's head) and the round directory holds `delta.txt`, the
`path:start-end` hunks changed since that head. The reviewer then
reviews only the delta, from `range.reviewed_from` (the prior head) to
the PR head: a finding outside it can only be a follow-up, except a
high. An empty
delta (the same head again) reviews the
whole PR from the merge base instead, never an empty range. A change
that adds or modifies no lines (a deletion) also reviews the whole PR,
with the scope `full: the change since the prior round adds no lines`
and no `delta.txt`, so every finding blocks as new.

## A rebase

The delta stands in for the whole PR only when the new head descends
from the prior round's head. After a rebase the round reviews the whole
PR from the merge base and writes no `delta.txt`, so every finding
blocks as new. `round.json`'s `range.review_scope` says which: `delta`,
or `full: <why>`.

## A base merge

A merge of the base branch into the PR keeps the delta to the PR's own
code. When the merge base moved since the prior round,
`range.reviewed_from` is a baseline commit instead of the prior head:
the prior head merged onto the new merge base. `delta.txt`, the
reviewer's range, and the critic's diff then hold only the PR's own
changes since the prior round, conflict resolutions included, and none
of the base's. A finding on the base's lines reads `reviewed`.

When the base merge is the only change since the prior round (the
head's tree equals the baseline's), a round other than the convergence
round (below) reviews nothing:
`range.review_scope` starts with `none:`, `runs` is empty,
`reviewer_complete` is `false`, and nothing is billed. A PR change
with no added lines (a deletion) is still a change and reviews the
whole PR.

## The convergence round

The convergence round runs no reviewer and no per-commit retry, so
nothing is billed for the reviewer. `round.json` records the scope
`full: this is the convergence round` (the whole PR, from the merge
base to the head), empty `runs`, and `reviewer_skipped: "convergence"`,
also after a base merge. `delta.txt` stays as the round computed it, so
a finding blocks or follows up as it did when the reviewer ran.

## A partial prior round

A `partial` prior round does not send the next round back to the whole
PR: the same caps re-fail the same files. Its unfinished files go to
`prior-unfinished.txt`, and `critic-input.sh` hands the critic their
whole-PR diff, where only a high finding blocks.

## The reviewer's range

The reviewer's range is `origin/<base>..<headRefOid>` in merge-base
mode on a full-scope round, and `<range.reviewed_from>..<headRefOid>`
on a delta round. After a base merge it runs from the baseline to a
commit that has the head's tree and only the baseline as parent.
