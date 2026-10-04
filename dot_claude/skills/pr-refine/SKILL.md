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
  (2026-10-03, ryankanno/dotfiles#39): adversarial findings ran 4, 6,
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

## 1. Read the round

Select the newest matching comment: its first line is the marker
`<!-- pr-loop-comment -->` and its author is you. The marker sits on the
first line, so a marker quoted inside a finding cannot forge a round
comment.

```bash
gh api user --jq .login
gh pr view <n> --json comments --jq '[.comments[] | select(.author.login == "<login>") | select(.body | startswith("<!-- pr-loop-comment -->"))] | last | .body'
```

The verdict line is one of
`No issues found.`, `<n> finding(s).`, or
`unrecovered (the reviewer produced no review text)`.

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

Rejected findings never reach the PR comment; they go in the loop's
final report.

## 3. Fix under TDD

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

## 6. Re-run the round

Run the full review round exactly as
`~/.claude/skills/pr-review/SKILL.md` defines it, over the new head
SHA, and post the round's comment per `report-template.md` with the
round number incremented.

## 7. Report back

Clean or findings-remaining, to the orchestrator or the human, with
the judgment calls listed. The convergence decision is never this
skill's: only the orchestrator's own review plus gate declares the
branch clean.

## Never

- Never fix a finding by adding machinery beyond it.
- Never force-push, and never push before the round's gate is green.
- Never report an empty reviewer result as clean or as a failure.
- Never post a comment that failed the scan.
- Never suppress a failure to pass the gate.
