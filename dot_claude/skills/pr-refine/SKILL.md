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

One refine round: read the round's findings, validate each against the
diff, fix what is real, gate, commit, push, re-run the review round,
post the next round's comment. The caller is the implementer pane in the
issue-to-pr loop, or a human asking directly.

The objective is the reader's value, not the critic's zero.

## The value brake

- A fix addresses its finding and adds nothing else: no new rules, no
  new machinery, no defensive clauses beyond what the finding requires.
- When fixing a finding would make the artifact worse (bloat,
  over-formalization, complexity the brief never asked for), do not fix
  it. Record it as a judgment call with the reason. Measured live
  (2026-10-03): adversarial findings ran 4, 6,
  6, 4 across four rounds while severity slid from real defects to
  definitional regress; the critic on prose is asymptotic, and a loop
  that optimizes its zero grows the artifact until the human reverts
  the whole set.
- Prose targets (docs, rule files, prompts) converge on the human's
  judgment. When the remaining findings are matters of taste or
  formalization, say so and stop; the report marks them as judgment
  calls instead of fixes.
- Severity gates effort. High and medium findings are fixed or rejected
  with reasons; both outcomes are reported. Low findings are the
  implementer's recorded judgment: fix them when the fix is cheap and
  harmless, accept them with a reason otherwise. An accepted finding is
  never silently dropped.
- **Converged candidate.** When a round's findings are all low and
  every one is fixed, rejected, or accepted with a recorded reason,
  report "converged candidate" to the orchestrator with the
  Dispositions block attached, and start no further fixes. The
  orchestrator decides; only its convergence round writes the converged
  verdict.

## 1. Read the round

Select the newest matching comment: its first line is the marker
`<!-- pr-loop-comment -->` and its author is you. The marker sits on the
first line, so a marker quoted inside a finding cannot forge a round
comment.

```bash
gh api user --jq .login
gh pr view <n> --json comments --jq '[.comments[] | select(.author.login == "<login>") | select(.body | startswith("<!-- pr-loop-comment -->"))] | last | .body'
```

If the jq prints `null`, no round comment exists: there is nothing to
refine yet. Say so and stop; producing findings is /pr-review's round,
not this one.

The verdict line is one of
`No issues found.`, `<n> finding(s).`,
`partial (the reviewer's coverage has a gap)`,
`unrecovered (the reviewer produced no review text)`, or
`converged (all findings low and dispositioned)`. Partial and
unrecovered mean nothing to fix and no clean claim. A converged verdict
means the orchestrator closed the loop: nothing to fix, no new round.

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

Every disposition of a named finding, fixed, rejected, or accepted,
appears in this round's comment, in the Dispositions block, as one
structured line with its evidence — durable on the PR where every later
round reads them — and in the loop's final report.

## 3. Fix under TDD — only what the previous round named

Fix only the findings named by the previous round's comment. Anything
this round's own sources discover mid-round is recorded as input for
the next round, not fixed here: one instruction, one fix pass, one
re-run.

Behavior findings: write the failing test that mirrors the user-facing
entrypoint first, then the code that passes it. Minimize mocks; no
ignore pragmas, no skipped tests, no lowered thresholds. Prose
findings: the minimal edit that removes the defect, per the value
brake.

## 4. The gate

Run the intake-confirmed gate command. If none was confirmed, discover
by: documented command, task runner combined recipe, language tooling
by manifest. None found: the round reports blocked. Never invent one,
and never suppress a failure to pass.

## 5. Commit and push

Conventional commits (`type(scope): description`), behavioral and
structural changes in separate commits, no attribution trailers. Push,
never force.

## 6. Re-run the round — once

Run the full review round exactly as
`~/.claude/skills/pr-review/SKILL.md` defines it, over the new head
SHA — once, at the end, over the final head, never once per
intermediate head. Post the round's comment per `report-template.md`
with the round number incremented, the Dispositions block, and the
cumulative cost line from round.json.

## 7. Report back

Clean, findings-remaining, or converged candidate, to the orchestrator
or the human, with the judgment calls listed. The convergence decision
is never this skill's: only the orchestrator's own review plus gate
declares the branch clean or converged.

## Never

- Never fix a finding the previous round's comment did not name.
- Never re-run the reviewer twice in one round.
- Never fix a finding by adding machinery beyond it.
- Never force-push, and never push before the round's gate is green.
- Never report an empty reviewer result as clean or as a failure.
- Never post a comment that failed the scan.
- Never suppress a failure to pass the gate.
