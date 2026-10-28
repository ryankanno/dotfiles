---
name: pr-refine
description: >-
  Use when asked to fix the findings a review round posted on a pull
  request: "fix the review findings", a refine instruction from the
  issue-to-pr loop, or after pushing a fix and wanting the next round.
  Reads the newest pr-loop comment, validates every finding against the
  diff, fixes under TDD, runs the gate, commits, pushes, re-runs the
  review round, and posts the next round's comment. Not for running the
  review itself (/pr-review) or the whole loop (/issue-to-pr).
---

# pr-refine

The caller is the implementer pane in the issue-to-pr loop, or a human
asking directly. The objective is the reader's value, not the critic's
zero.

## The value brake

- A fix addresses its finding and adds nothing else: no new rules, no
  new machinery, no defensive clauses beyond what the finding requires.
- When fixing a finding would make the artifact worse (bloat,
  over-formalization, complexity the brief never asked for), do not fix
  it. Record it as a judgment call with the reason: the critic on prose
  never reaches zero, and a loop that optimizes its zero grows the
  artifact until the human reverts the whole set.
- Prose targets (docs, rule files, prompts) converge on the human's
  judgment. When the remaining findings are matters of taste or
  formalization, say so and stop; the report marks them as judgment
  calls instead of fixes.
- Severity gates effort. High and medium findings are fixed or rejected
  with reasons; both outcomes are reported. Low findings are the
  implementer's recorded judgment: fix them when the fix is cheap and
  harmless, accept them with a reason otherwise. An accepted finding is
  never silently dropped.
- **Converged candidate.** When a round's blocking findings are all low
  and every one is fixed, rejected, or accepted with a recorded reason,
  it is a converged candidate: start no further fixes. In the
  issue-to-pr loop, the implementer runs the convergence round next;
  only a convergence round writes the converged verdict, and the
  orchestrator ratifies it.

## 1. Read the round

Print the newest round's comment:

```bash
$HOME/.claude/skills/issue-to-pr/tools/round-comment.sh <owner/repo> <n>
```

It prints the newest usable comment: the round's `comment.md` first, so
the refine never waits for the post, then your round comment on the PR.

On a repository that is not owned (pr-review §8), read the round from
`comment.md` only: no round comment is on the PR.

When the tool exits 1, no round comment exists: there is nothing to
refine yet. Say so and stop; producing findings is /pr-review's round,
not this one. When it exits 2 (a usage error, an unset `HOME`, or a
missing `scan.sh`), fix the call or the environment and run it once
more. On a second exit 2, or an exit other than 0, 1 or 2 (a failed
read, or a missing `gh` or `jq`), report its last stderr line and stop.
In the issue-to-pr loop, the pane stops with
`blocked: round-comment.sh exit <code>: <stderr line>`.

The verdict line is one of the lines in the verdict list of
`$HOME/.claude/skills/pr-review/report-template.md`. Each line there
says what it leaves this round to fix.

## 2. Validate every finding

Read the diff and check each finding against it:

```bash
git diff origin/<base>...<head>
```

- The diff contains the claim: the file, the line, the behavior. A
  finding the diff does not contain is rejected, and the reason is
  recorded.
- The finding describes a defect or a real risk, not a preference.
- Fixing it stays inside the brief's scope.
- The finding is not already dispositioned: check the prior rounds'
  Dispositions blocks; a re-flag without materially new evidence is
  rejected with a pointer to the recorded reason.
- The finding is not already known. Before you fix a high or medium
  finding, search the open issues (`gh issue list --search "<subject>"`)
  and the recent commits on the finding's file
  (`git log --oneline <head>..origin/<base> -- <file>`). A duplicate is
  rejected as `known: tracked in #N` or `known: fixed in <sha>`. An
  issue this PR closes is not a duplicate.
- A claim about runtime or framework semantics is settled with the
  cheapest probe (a test, or a script run in the repo's environment)
  before it is fixed, rejected or accepted. The probe's output is the disposition's
  evidence.

The reason in an orchestrator's refine instruction is materially new
evidence. No check above rejects the finding it names on the recorded
reason that the instruction overrules.

Every disposition of a named finding, fixed, rejected, or accepted,
appears in this round's comment, in the Dispositions block, as one
structured line with its evidence.

## 3. Fix under TDD — only what the previous round named

Fix only the blocking findings named by the previous round's comment,
under its **Findings:** heading, or the one finding an orchestrator's
refine instruction names (issue-to-pr §6); its **Follow-ups:** are not
this round's work. Anything
this round's own sources discover mid-round is recorded as input for
the next round, not fixed here: one instruction, one fix pass, one
re-run.

Behavior findings: write the failing test that mirrors the user-facing
entrypoint first, then the code that passes it. Minimize mocks; no
ignore pragmas, no skipped tests, no lowered thresholds. Prose
findings: the minimal edit that removes the defect, per the value
brake.

## 4. The gate

Run the intake-confirmed gate command with its words as written: add no
flags. Judge it by its exit code, not by a summary line in its output:

```bash
<gate command> >"<log file>" 2>&1; echo "gate exit=$?"
```

Read only the log's tail, and only when the exit is not 0. Run the gate
once per push. The exit code decides whether you push. With no
confirmed gate, discover one as issue-to-pr §1 item 4 does. None found:
the round reports blocked.

## 5. Commit and push

Conventional commits, behavioral and structural changes in separate
commits, no attribution trailers. Push, never force.

## 6. Re-run the round — once

Write this round's Rejected and Accepted lines, as §2 records them, to
`refine-dispositions.md` in the new round's directory before you run
the round: `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/`, with
`<N>` the new round's number. Create the directory when it is missing,
also when you have no such lines. A resume counts a refine whose round
stopped before its `rounds.txt` line by that directory
(`resume-state.sh`). Write the lines as `report-template.md`'s
Dispositions block writes them:
`- Rejected:` or `- Accepted:` at column 0, wrapped text indented.
A `- Fixed:` line stays out of the file: the round reads only the other
two, and the scan reads the whole file. The round scans the file: a hit
stops the round with exit 2 (pr-review §1).

Run the full review round exactly as
`$HOME/.claude/skills/pr-review/SKILL.md` defines it, over the new head
SHA — once, at the end, over the final head, never once per
intermediate head. Pass `--expect-head` with the SHA you pushed
(`git rev-parse HEAD`). Pass the `--effort`, `--timeout`, `--max-tools`,
`--max-tokens-budget`, `--concurrency` and `--exclude` the loop's rounds
use, when the dispatch prompt or the caller names them. Write, scan and
post the round's comment per pr-review §6 to §8.

## 7. Report back

Clean, findings-remaining, or converged candidate, with the judgment
calls listed. In the issue-to-pr loop, the implementer continues its
round loop on this result; only the orchestrator's ratification
declares the loop clean or converged.

## Never

- Never force-push.
- Never post a comment that failed the scan.
