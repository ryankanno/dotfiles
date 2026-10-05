---
name: issue-to-pr
description: >-
  Use when asked to take an issue or task to a finished, reviewed PR in one
  unattended run: an issue number or URL, a todo item in a markdown file, or
  an issue in an HTML file, plus "run the loop on this", "work this issue
  through to a PR". Covers intake, implementation in a fresh workmux window,
  the PR, two independent reviews, a findings comment on the PR, refine
  rounds, and a final report. Not for a single review round (/pr-review) or
  for fixing findings (/pr-refine).
---

# issue-to-pr

One command per task. Take a task from an intake source, implement it with
TDD in a fresh workmux window, file a PR, run two independent reviews over
the PR's ref range, post the findings as a comment, refine until clean or
capped at 3 rounds, and end with a report. After intake, everything runs
unattended; the human gets the report and nothing else.

The final message of a run IS the report. A future queue runner invokes
this skill once per task and reads that message. Keep it self-contained.

The whole loop as one picture: [`flow.md`](flow.md).

Fixed process, swappable tools: the reviewer and the critic are named
slots resolved through `~/.claude/skills/issue-to-pr/tools/manifest.json`
and the bindings under `tools/`. Never hardcode a tool binary from a
manifest slot into a command; read the manifest, then use the binding.

## 1. Intake

One interactive moment. Collect and confirm, then go silent:

1. **The task.** Accept any of:
   - gh issue: `123`, `#123`, a URL, or `owner/repo#123`
     (extract: `gh issue view <n> --json title,body`)
   - markdown todo: `<path>:<line>` of a `- [ ]` item
     (extract: the item line plus its indented detail lines)
   - HTML file: `<path>` plus the element to read
     (extract: that element's text)
2. **The brief.** Write the extracted task to a brief file: title, body,
   acceptance criteria if present, and the source locator. Show it. Wait
   for confirmation. Extraction errors surface here or never.
3. **The layout.** Harness plus prompt stack ride together in one workmux
   layout name: `claude-sp`, `claude-mp`, `opencode-sp`, `opencode-mp`
   (sp = superpowers, mp = mattpocock). Confirm which. The opencode
   layouts require the `sp`/`mp` agents to exist on the opencode side;
   a missing agent fails the dispatch loudly at the pane.
4. **The gate.** Ask for the project's gate command. If unknown, discover
   by: documented command, task runner combined recipe, language tooling
   by manifest. Still nothing: later rounds report blocked rather than
   inventing one.
5. **The reviewer.** Default from the manifest. Override only if asked.
6. **The grill.** On or off. On when the task leaves decisions to the
   human (product calls, open questions in the source): the implementer
   writes its plan, then grills it with the human in the workmux window,
   using the grill-me skill, before any code. The human answers there,
   not here, so intake stays the one moment with the orchestrator. Off
   for tasks whose source already settles every decision.

The grill is the one sanctioned pause after intake. While it runs, the
pane waits on the human: `workmux status` shows it waiting, and that is
not pane death. Do not redispatch, nudge, or answer for the human; wait
until the pane moves on to code or files the PR.

**The loop never closes anything.** `Closes #<n>` goes in the PR body for
gh sources and closes on merge. Markdown and HTML sources are never
mutated; checkboxes stay unticked; the PR is the record.

## 2. Idempotency before creation

The `<branch-name>` is deterministic,
`loop/<source-type>-<slug>-<hash8>`, and computed by the tool, never by
hand. `<source-type>` is `gh`, `md`, or `html`; the item text is the
extracted task from the brief.

```bash
~/.claude/skills/issue-to-pr/tools/branch-name.sh \
  --type <source-type> --locator <source locator> --title <title> \
  < <item-text-file>
gh pr list --state open --head <branch-name>
```

Every step below spells the full `<branch-name>` it printed; there is no
shorter form to substitute.

An existing PR means a previous run: do not create anything. Verify its
state and resume the loop at step 5. If the prior run left
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md`, read it and
carry its verdict forward into the resume: a capped-unrecovered resume
inherits the remaining findings instead of rediscovering them, and a
blocked resume inherits its reason. A task whose source text was edited
re-keys the hash; if an older PR for the same source surfaces, say so in
the final report rather than orphaning it silently.

## 3. Dispatch

Write the dispatch prompt from
[`dispatch-prompt-template.md`](dispatch-prompt-template.md) and the
confirmed brief, to a file. Then:

```bash
workmux add <branch-name> -b -l <layout> -P <prompt-file>
```

Never `-a`: it is silently ignored, and `-l` refuses to combine with it.
The pane command comes from the layout; the prompt is the task.

Verify the pane binary with tmux, never a capture and never the agent's
word:

```bash
tmux list-panes -t <session>:<index> -F '#{pane_current_command}'
```

The pane must name the chosen harness's binary. Monitor with
`workmux status` and `workmux capture <handle>`.

## 4. The PR, verified and bound to this loop

The implementer pushes and files the PR (`Closes #<n>` for gh sources).
Verify it yourself; never trust the self-report. A real number pointing
at someone else's PR is the hallucination to catch here, so bind the
identity, not just the existence:

```bash
gh pr list --state open --head <branch-name>
gh pr view <n> --json state,headRefName
```

The PR counts as verified only if its head is `<branch-name>`. The
round script re-checks with `--expect-branch` before any review runs.

## 5. The review round

Run the review round exactly as `~/.claude/skills/pr-review/SKILL.md`
defines it, over the PR's ref range. Reviews never touch the checkout's
`HEAD`.

## 6. Refine rounds

If the round has findings, send the implementer pane a refine instruction
naming the PR:

```bash
workmux send <handle> "Refine round <N> on PR <n>: run the pr-refine skill."
```

The implementer fixes under TDD, runs the gate, pushes, re-runs the
review round, and posts the round's comment itself, per
`~/.claude/skills/pr-refine/SKILL.md`. Watch it with `workmux status` /
`capture`, and verify each round's push with `gh pr view` before the next
step.

**Cap: 3 refine rounds.** After a third round with findings remaining,
stop and report unrecovered.

**Converged candidate.** When the implementer reports a converged
candidate (a round whose findings were all low and every one fixed,
rejected, or accepted with a recorded reason, per pr-refine's value
brake), send no further refine instructions; go straight to
convergence. The asymptote ends where the dispositions do.

## 7. Convergence

Only this skill declares the branch clean or converged, and only on its
own evidence. When the implementer reports clean, a converged
candidate, or the cap hits, run the full review
round yourself on the final SHA, and run the gate yourself. Gate the
PR's code, not your checkout: run the gate in the implementer's
worktree (`workmux path <handle>` prints it), after verifying the
worktree's HEAD equals the PR's headRefOid
(`git -C <worktree> rev-parse HEAD`). A green gate on any other tree
declares nothing.

- both clean: the loop ends clean.
- findings all low and every one dispositioned: your convergence
  comment's verdict is `converged (all findings low and
  dispositioned)` and the loop ends converged, with the accepted
  judgment calls listed in the final report.
- findings otherwise: one more refine round while rounds remain under
  the cap; when the cap is spent, the loop ends unrecovered, with your
  findings quoted in the report.

## 8. The final report

The last message of the run, verbatim to the future runner:

- task ref (source locator and title), PR link
- verdict: `clean` (convergence round found nothing and the gate printed
  green), `converged` (findings existed but the convergence round found
  every one low and dispositioned; the accepted judgment calls are
  listed), `capped-unrecovered` (findings remain after 3 rounds), or
  `blocked` (pane death after redispatch, no gate found, scan hit, or
  a partial or unrecovered reviewer with nothing from any source)
- per-round one-liners: round number, short SHA, verdict, who ran it
- the gate: the command and its final printed result
- anything a scan blocked, with the line it caught
- reviewer session ids and token totals (the last round's `round.json`
  `cumulative_tokens`, which counts the evidence that stands;
  superseded runs stay on disk uncounted), reviewer and critic
  bindings used, ocr version
- the PR comment links, one per round

Before the final message is spoken, write the report verbatim to
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md`, the same
directory that holds the round dirs. The final message remains the
report; the file is its durable copy, the exact text, no summary layer.

## Failure policies

- **Pane death or failed pane check:** redispatch once by reopening the
  surviving worktree (`workmux open <handle>`, worktree and branch
  persist), with a re-entry prompt. Second failure: blocked.
- **No gate found:** the round reports blocked. Never invent one.
- **Scan hit on a comment body:** do not post it. Record the finding; it
  surfaces in the final report. Unattended does not mean leaked.
- **Empty reviewer result:** handled inside the review round (retry once
  per-commit). Two empties: the round is unrecovered, never clean and
  never failing.
- **PR creation failed:** capture the pane's error, report blocked. Do
  not redispatch the whole task.
- **Degraded critic harness:** if your own critic subagent cannot run,
  relay the critic through the implementer's pane: `workmux send` the
  critic prompt, and read the findings from its report-back. The
  commissioned findings still do not create a round: they enter the next
  round as caller-supplied input, the round numbering never moves, and
  no partial comment posts.

## Never

- Never review `HEAD` instead of the PR's range.
- Never close the issue, tick a source checkbox, or merge the PR.
- Never force-push, and never push before the round's gate is green.
- Never post a comment that failed the scan.
- Never trust an agent's self-report where a command can verify.
