---
name: pr-review
description: >-
  Use when asked to run one native review round on a pull request and post
  it as a comment: "review this PR", "run a review round", or as a step of
  the issue-to-pr loop. Runs the reviewer binding (ocr by default) and the
  adversarial critic over the PR's ref range, adds the caller's own read,
  and posts the standard report comment. Not for fixing findings
  (/pr-refine) and not for the whole loop (/issue-to-pr).
---

# pr-review

One review round over a pull request's ref range: the reviewer binding,
the adversarial critic binding, the caller's own read, one report
comment. The caller (the issue-to-pr orchestrator, the implementer in a
refine round, or a human) assembles nothing by hand; this skill defines
every step.

Two independent reviews plus the caller's read is the whole point: a
single reviewer that found nothing proves only that one reader was
unpersuaded.

## 1. Run the round

The range mechanics live in the slot's tested script, not in this
skill's prose:

```bash
~/.claude/skills/issue-to-pr/tools/pr-round.sh \
  --repo <repo> --pr <n> --round <N> \
  --brief <brief-file> --expect-branch <branch-name>
```

The reviewer reads only its background file, never the PR comments, so
the script joins the brief with every Rejected and Accepted line from
the Dispositions blocks of this loop's own round comments (marker on
line 1, your own author) into `background.md` in the round directory.
Fixed lines stay out: a fix the reviewer still flags is a fix to
re-check. `--dispositions <file>` replaces the lines read from the
comments with the file's content.

The background has a size limit: the manifest's
`reviewer_background_limit` (8000 characters for ocr, which aborts on
anything longer before it reviews a line). The dispositions fill the
room the brief leaves, newest first, and the background says how many
older ones gave way. A brief over the limit on its own, or one whose
assembled background overflows once the standing dispositions join it,
stops the round with exit 2 before any review runs, leaving the round
dir untouched: condense it to the
task (its asks,
the settled decisions, the constraints) and rerun, never pass a
dispatch prompt or loop instructions as the brief.

From round 2 on, `round.json` carries `range.prior_head` (the previous
round's head) and the round directory holds `delta.txt`, the
`path:start-end` hunks changed since that head. The reviewer then
reviews only the delta, from `range.reviewed_from` (the prior head) to
the PR head: a finding outside it can only be a follow-up, except a
high. High severity blocks anywhere, in the delta or out, and the
caller counts it under Findings. An empty
delta (the same head again, as in a convergence round) reviews the
whole PR from the merge base instead, never an empty range.

`--expect-branch` binds the round to this loop's branch: a PR whose
head is any other branch is a hallucinated number, and the script exits
3 before anything reviews or posts. Omit it only when the caller
cannot know the branch (a human's standalone review). The script
resolves the range from the PR (never the checkout's `HEAD`), fetches
the refs, runs the active reviewer binding over
`<range.reviewed_from>..<headRefOid>`, applies the per-commit
empty-retry policy once per commit in that range, and prints the round
directory
whose `round.json` carries the range, the identity, every run (mode,
directory, status, session id, exit code), and `reviewer_complete`.

## 2. Read round.json

**`reviewer_complete: true`** with zero findings is a clean review:
report it as clean. **`reviewer_complete: false`** takes one of two
shapes, read from `runs[].status`:

- **Partial** (a run is `partial`): the reviewer produced review text,
  but part of the range went unreviewed (failed files, or a group that
  lost a review pass). Its findings count like any other source's.
  With nothing from any source, the verdict is `partial (the
  reviewer's coverage has a gap)`.
- **Unrecovered** (no run is `partial`): the reviewer produced no
  review text, whatever runs it attempted. With nothing from any
  source, the verdict is `unrecovered (the reviewer produced no review
  text)`.

Either way, findings from any source make the verdict count them, and
the visible `**Reviewer:**` line names the gap per report-template.md.
Neither shape is clean and neither is a failure: /pr-refine reads both
as nothing to fix, and the loop cannot declare the branch clean off
that round.

The round's cost is a fact the comment carries: `round.json`'s
`cumulative_tokens` becomes the template's Cost line, so a reader can
see what the loop has spent to date. The critic's tokens are not in
`round.json` (the critic is a subagent, not the reviewer binding): take
them from the usage the harness reports when the subagent returns, and
put them on the Cost line beside the reviewer's. When the harness
reports none, the line says so; a guessed number is never written.

## 3. The adversarial critic

Resolve the critic from the manifest and follow its binding file
(`~/.claude/skills/issue-to-pr/tools/<critic>/binding.md`) for how to
spawn it: a fresh, clean-context subagent whose prompt is the output of
`critic-input.sh`, verbatim. Never write the critic's prompt yourself:
the script carries the instructions, the brief, the findings this
round's diff answers, the settled dispositions, and the one diff, and
leaves out the follow-ups.

```bash
~/.claude/skills/issue-to-pr/tools/subagent/critic-input.sh \
  --repo <repo> --round-dir <round-dir> --brief <brief-file>
```

Its findings arrive numbered with file, line, the claim, the input or
state that reaches it, the harm, severity, and how it checked. Findings
that do not reference that diff are dropped, per the binding's
contract. Its "Unconfirmed candidates" section stays verbatim in the
collapsed Critic block and never enters the Findings or Follow-ups
lists: an unconfirmed candidate is not a finding.

## 4. The caller's own read

Read the diff against the brief yourself:

- **Scope creep:** anything the diff changes that the brief does not
  ask for.
- **Weakened tests:** assertions that would survive deleting the
  feature, tests weakened to pass, tests deleted. A deleted test is a
  high-severity finding.
- **Gate output:** in refine and convergence rounds, scrutinize the
  gate transcript, not its exit code alone.
- **Corroboration:** agreement between two sources counts only when
  both could see the code the claim is about. A factual dispute
  settles against the code, not by counting sources.
- **Same head:** if this round runs over the same head as the prior
  round, cite new evidence against that verdict or defer to it.

## 5. Blocking or follow-up

Classify every finding from every source against the round's delta:

```bash
~/.claude/skills/issue-to-pr/tools/finding-scope.sh <round-dir> <path>:<start>[-<end>]
```

- **Blocking:** high severity anywhere, or `new`: on a line changed
  since the prior round's head. Every finding in round 1 and every
  finding without a line prints `new`.
- **Follow-up:** medium or low, and `reviewed`: on code an earlier
  round already reviewed. Fresh-context reviewers find new edge cases
  in reviewed code every round, so letting those block keeps the loop
  from ever converging (measured on PR 40: 24 of 32 findings in rounds
  3 to 6 sat on reviewed code). Follow-ups are listed, never fixed in
  the loop and never dispositioned; the final report hands them to the
  human.

## 6. Assemble the comment

Follow [`report-template.md`](report-template.md) exactly: marker first
line, heading, verdict, visible consolidated findings tagged by source,
collapsed blocks with each source's output verbatim. The reviewer's
sections render with the binding's renderer, once per run recorded in
`round.json` (`render.sh <runs[].dir>`), completed or skipped alike:
thin coverage and a skipped run must read as what they are.

The verdict line is machine-read by /pr-refine; keep the protocol exact,
one of: `**Verdict:** No issues found.` when every source ran and
produced no blocking finding, `**Verdict:** <n> finding(s).` when <n>
blocking findings exist, `**Verdict:** partial (the reviewer's coverage has a gap).` when
the binding ended partial with nothing else to report, or
`**Verdict:** unrecovered (the reviewer produced no review text).` when
the binding ended unrecovered with nothing else to report.

## 7. Scan before posting

Write the body to a file, never inline. Scan it before it leaves the
machine:

```bash
~/.claude/skills/issue-to-pr/tools/scan.sh <file>
```

The script rewrites home paths to `~` in place. Exit 0: post the file.
Exit 1: it printed each remaining hit (another home path, a temp path,
or a token); **do not post**. Record the lines. Unattended does not mean
leaked; the blocked post surfaces in the loop's final report.

## 8. Post

```bash
gh pr comment <n> --body-file <file>
```

Record the comment URL and the round directory: the final report needs
the session ids and token totals from the round's `review.json`.

## Never

- Never review `HEAD` or the checkout's branch tip.
- Never soften or summarize the binding's rendered output; verbatim or
  not at all.
- Never post a comment that failed the scan.
- Never report an empty result as clean or as a failure.
