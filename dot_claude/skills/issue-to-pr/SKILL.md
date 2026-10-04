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

**The loop never closes anything.** `Closes #<n>` goes in the PR body for
gh sources and closes on merge. Markdown and HTML sources are never
mutated; checkboxes stay unticked; the PR is the record.

## 2. Idempotency before creation

The `<branch-name>` is deterministic:
`loop/<source-type>-<slug>-<hash8>`, where `<hash8>` is the first 8
hex characters of sha256 over the UTF-8 bytes of the source locator, a
newline, then the item text, in that order. Every step below spells the
full `<branch-name>`; there is no shorter form to substitute.

```bash
gh pr list --state open --head <branch-name>
```

An existing PR means a previous run: do not create anything. Verify its
state and resume the loop at step 5. A task whose source text was edited
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

## 7. Convergence

Only this skill declares the branch clean, and only on its own evidence.
When the implementer reports clean (or the cap hits), run the full review
round yourself on the final SHA, and run the gate yourself. Gate the
PR's code, not your checkout: run the gate in the implementer's
worktree (`workmux path <handle>` prints it), after verifying the
worktree's HEAD equals the PR's headRefOid
(`git -C <worktree> rev-parse HEAD`). A green gate on any other tree
declares nothing.

- both clean: the loop ends clean.
- findings: one more refine round while rounds remain under the cap;
  otherwise the loop ends unrecovered, with your findings quoted in the
  report.

## 8. The final report

The last message of the run, verbatim to the future runner:

- task ref (source locator and title), PR link
- verdict: `clean` (convergence round found nothing and the gate printed
  green), `capped-unrecovered` (findings remain after 3 rounds), or
  `blocked` (pane death after redispatch, no gate found, scan hit, or
  two empty reviewer results)
- per-round one-liners: round number, short SHA, verdict, who ran it
- the gate: the command and its final printed result
- anything a scan blocked, with the line it caught
- reviewer session ids and token totals (sum from the round dirs'
  `review.json`), reviewer and critic bindings used, ocr version
- the PR comment links, one per round

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

## Never

- Never review `HEAD` instead of the PR's range.
- Never close the issue, tick a source checkbox, or merge the PR.
- Never force-push, and never push before the round's gate is green.
- Never post a comment that failed the scan.
- Never trust an agent's self-report where a command can verify.
