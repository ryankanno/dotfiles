# Review ranges

How `pr-round.sh` picks a round's range, and what `round.json` records
for it. The script computes all of it, and `finding-scope.sh`
classifies each finding against it. pr-review §1 and §2 link here.

## The delta

From round 2 on, `round.json` carries `range.prior_head` (the previous
round's head) and the round directory holds `delta.txt`, the
`path:start-end` hunks changed since that head. The reviewer then
reviews only the delta, from `range.reviewed_from` (the prior head) to
the PR head: a finding outside it can only be a follow-up, except a
high. An empty delta (the same head again) reviews the whole PR from
the merge base instead, never an empty range. A change that adds or
modifies no lines (a deletion) also reviews the whole PR, with the
scope `full: the change since the prior round adds no lines` and no
`delta.txt`, so every finding blocks as new.

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

On a `none:` scope, skip pr-review steps 3 to 5: no source runs. Post a
comment per report-template.md with the verdict line its list gives
for a `none:` scope and the round dir's `prior-findings.md`, verbatim,
as its `**Findings:**` section when the file exists. The prior round's
blocking findings then stand for /pr-refine and for the next round.

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

## A reviewer that did not finish

`reviewer_complete: false` takes one of three shapes, read from
`runs[].status`:

- **Partial** (a run is `partial`, or a `commit:` run is `complete`):
  the reviewer produced review text,
  but part of the range went unreviewed (failed files, a group that
  lost a review pass, or commits whose retry produced no review text).
  Its findings count like any other source's.
- **Nothing reviewable** (the range run is `skipped`): the reviewer
  selected no file in the range (docs, tests, lockfiles), so it had
  nothing to review, and no per-commit retry runs.
- **Unrecovered** (none of these): the reviewer produced no
  review text, whatever runs it attempted.

With nothing from any source, each shape has its own verdict line in
report-template.md's verdict list.
In every shape, findings from any source make the verdict count them,
and the visible `**Reviewer:**` line names the gap per
report-template.md. No shape is clean and none is a failure:
/pr-refine reads each as nothing to fix, and the loop cannot declare
the branch clean off that round.

## The reviewer's range

The reviewer's range is `origin/<base>..<headRefOid>` in merge-base
mode on a full-scope round, and `<range.reviewed_from>..<headRefOid>`
on a delta round. After a base merge it runs from the baseline to a
commit that has the head's tree and only the baseline as parent.
