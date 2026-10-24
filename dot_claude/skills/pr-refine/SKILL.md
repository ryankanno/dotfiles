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
- Only blocking findings are refine work. Follow-ups sit on code an
  earlier round already reviewed, or are low findings on test
  assertions or comment wording that the previous refine added
  (pr-review §5); they are listed for the human, never fixed or
  dispositioned here.
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

Read the newest round from disk first: `comment.md` in the newest
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/` that has a
`round.json`. That file is the scanned text the round posts, and it
exists before the post, so the refine never waits for one. The next
round's `pr-round.sh` skips a file that lacks the marker
`<!-- pr-loop-comment -->` on line 1, the `## Review round <N>:` heading
for its folder, or the template's last line, `*Round <N> | ...*`, or
that then fails `$HOME/.claude/skills/issue-to-pr/tools/scan.sh`. Check
it the same way, in that order; when it fails, treat that round as
having no `comment.md`.

On a repository that is not owned (pr-review §8), read the round from
`comment.md` only: no round comment is on the PR.

When that round has no `comment.md`, select the newest matching comment
on the PR: its first line is the marker `<!-- pr-loop-comment -->` and
its author is you. The marker sits on the first line, so a marker
quoted inside a finding cannot forge a round comment.

```bash
gh api user --jq .login
gh pr view <n> --json comments --jq '[.comments[] | select(.author.login == "<login>") | select(.body | startswith("<!-- pr-loop-comment -->"))] | last | .body'
```

If neither exists (no file, and the jq prints `null`), no round comment
exists: there is nothing to refine yet. Say so and stop; producing
findings is /pr-review's round, not this one.

The verdict line is one of
`No issues found.`, `<n> finding(s).`,
`partial (the reviewer's coverage has a gap).`,
`nothing reviewable (no files in the reviewer's scope).`,
`unrecovered (the reviewer produced no review text).`,
`nothing to review (only a base merge since the prior round).`, or
`converged (all blocking findings low and dispositioned).` Partial,
nothing reviewable and unrecovered mean nothing to fix and no clean
claim. Nothing to review
means no clean claim: its Findings are the prior round's, carried
verbatim, and you fix them like any round's. A converged verdict
means the convergence round closed the loop: nothing to fix, no new
round.

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

Fix only the blocking findings named by the previous round's comment,
under its **Findings:** heading; its **Follow-ups:** are not this
round's work. Anything
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
once per push. The exit code decides whether you push. The review
round's own read (pr-review §4) still scrutinizes the whole log. If
none was confirmed, discover
by: documented command, task runner combined recipe, language tooling
by manifest, plus the checks the commit hooks run. None found: the
round reports blocked. Never invent one,
and never suppress a failure to pass.

## 5. Commit and push

Conventional commits (`type(scope): description`), behavioral and
structural changes in separate commits, no attribution trailers. Push,
never force.

## 6. Re-run the round — once

Write this round's Rejected and Accepted lines, as §2 records them, to
`refine-dispositions.md` in the new round's directory before you run
the round: `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/`, with
`<N>` the new round's number. Create the directory when it is missing.
Write the lines as `report-template.md`'s Dispositions block writes them:
`- Rejected:` or `- Accepted:` at column 0, wrapped text indented.
A `- Fixed:` line stays out: the round reads only the other two, and the
scan reads the whole file. The round reads the file: its Rejected and Accepted lines join the
standing dispositions for the reviewer and the critic (pr-review §1).
The file passes `scan.sh` first: a hit stops the round with exit 2
before any review. Fix the file, then run the round again.

Run the full review round exactly as
`$HOME/.claude/skills/pr-review/SKILL.md` defines it, over the new head
SHA — once, at the end, over the final head, never once per
intermediate head. Pass `--expect-head` with the SHA you pushed
(`git rev-parse HEAD`). Pass the `--effort`, `--timeout`, `--max-tools`,
`--max-tokens-budget` and `--exclude` the loop's rounds use, when the dispatch prompt or
the caller names them. Write the
round's comment per `report-template.md`
with the round number incremented, the Dispositions block, and the
cumulative cost line from round.json. Post the round's comment per
pr-review §8: on a repository that is not owned, it stays a draft.

## 7. Report back

Clean, findings-remaining, or converged candidate, with the judgment
calls listed. In the issue-to-pr loop, the implementer continues its
round loop on this result; a human caller gets it as the report. The
loop's end state is never this skill's: only the orchestrator's
ratification declares the loop clean or converged.

## Never

- Never fix a finding the previous round's comment did not name as
  blocking.
- Never re-run the reviewer twice in one round.
- Never fix a finding by adding machinery beyond it.
- Never force-push, and never push before the round's gate is green.
- Never report an empty reviewer result as clean or as a failure.
- Never post a comment that failed the scan.
- Never suppress a failure to pass the gate.
