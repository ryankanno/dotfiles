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

**The implementer owns every review round; the orchestrator owns the
verdict.** The orchestrator runs no review; it ratifies the pane's
rounds (step 6). Two owners of rounds collided in the logs: duplicate
round comments and `pr-round.sh` exit 6.

The final message of a run IS the report. A future queue runner invokes
this skill once per task and reads that message. Keep it self-contained.

The whole loop as one picture: [`flow.md`](flow.md).

Fixed process, swappable tools: the reviewer and the critic are named
slots resolved through `$HOME/.claude/skills/issue-to-pr/tools/manifest.json`
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
   for confirmation. Extraction errors surface here or never. The
   reviewer reads this brief as its background, under the manifest's
   `reviewer_background_limit` (8000 characters for ocr), and later
   rounds add the standing dispositions to the same budget: keep the
   brief to about half the limit. A source too long for that (several
   issues, long bodies) is condensed to its asks, decisions, and
   constraints, not pasted whole. The brief is the task, never the
   dispatch prompt: push and loop instructions are not the reviewer's.
3. **The layout.** Harness plus prompt stack ride together in one workmux
   layout name: `claude-sp`, `claude-mp`, `opencode-sp`, `opencode-mp`
   (sp = superpowers, mp = mattpocock). Confirm which. The opencode
   layouts require the `sp`/`mp` agents to exist on the opencode side;
   a missing agent fails the dispatch loudly at the pane.
4. **The gate.** Ask for the project's gate command. If unknown, discover
   by: documented command, task runner combined recipe, language tooling
   by manifest. Still nothing: later rounds report blocked rather than
   inventing one. Also read the commit hooks (`.pre-commit-config.yaml`,
   and the directory `git rev-parse --git-path hooks` prints, which
   follows `core.hooksPath` and linked worktrees) and name their checks
   when you confirm
   the gate: a formatter the gate skips aborts each commit after a green
   gate.
5. **The reviewer.** Default from the manifest. Override only if asked.
   The same holds for its effort, timeout, tool cap and token budget:
   the binding's defaults (ocr: `medium`, `80` minutes, `200` tool
   rounds, `25000000` tokens) unless the human sets them. A set value
   goes to `pr-round.sh` as `--effort` / `--timeout` / `--max-tools` /
   `--max-tokens-budget` in every round of
   the loop, all run by the implementer through the dispatch prompt.
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
$HOME/.claude/skills/issue-to-pr/tools/branch-name.sh \
  --type <source-type> --locator <source locator> --title <title> \
  < <item-text-file>
gh pr list --state open --head <branch-name>
```

Every step below spells the full `<branch-name>` it printed; there is no
shorter form to substitute.

An existing PR means a previous run: do not create anything. Verify its
state and resume the loop at step 5. If no pane runs on the worktree,
reopen it with `workmux open <handle>` and the dispatch prompt from
[`dispatch-prompt-template.md`](dispatch-prompt-template.md), with its
"Resuming" section filled in: never a re-entry text of your own. Fill
its refine-round count and its convergence flag from
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/rounds.txt`, where the pane
writes one `<N> <kind>` line per round. Use only the round numbers
that have a `round-<N>/` folder, and for a number with two lines, the
last one: a pane that died before its round started leaves a line for
a round that never ran. The count is the number of `refine` rounds,
and the flag is the kind of the newest finished round. The round numbers do not give the count, because a
convergence round takes a number of its own. A PR with no `rounds.txt`
gets the template's unknown-count bullet. If the
prior run left
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md`, read it and
carry its verdict forward into the resume: a capped-unrecovered resume
inherits the remaining findings instead of rediscovering them, and a
blocked resume inherits its reason. A task whose source text was edited
re-keys the hash; if an older PR for the same source surfaces, say so in
the final report rather than orphaning it silently.

## 3. Dispatch

Write the dispatch prompt from
[`dispatch-prompt-template.md`](dispatch-prompt-template.md) and the
confirmed brief, to a file. Keep `--assignee @me` in its `gh pr create`
line only when this prints `ADMIN`, because the human takes PRs only on
repositories they own:

```bash
gh repo view --json viewerPermission -q .viewerPermission
```

Then:

```bash
workmux add <branch-name> -b -l <layout> -P <prompt-file>
```

Never `-a`: it is silently ignored, and `-l` refuses to combine with it.
The pane command comes from the layout; the prompt is the task.

Verify the pane binary with tmux, never a capture and never the agent's
word:

```bash
tmux list-panes -t <session>:<handle> -F '#{pane_current_command}'
```

`<handle>` is the window name that `workmux status` prints for this
worktree. Read it there after `workmux add`. Never derive it from the
branch name: workmux changes characters, and a branch name gives "can't
find window".

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

## 5. The implementer's round loop

The dispatch prompt's "Review rounds" section is the loop: round 1
after the PR, refine rounds capped at 3, the convergence round after
a refine (`--convergence`, the whole PR on the final head), then a stop
state. A clean round 1 is final: it already reviewed the whole PR.
Round numbers never repeat; `pr-round.sh` exit 6 means a number was
reused, or the pane's earlier run of that round died before its
`round.json`.

Watch the pane with `workmux status` / `capture`. Verify each round's
push with `gh pr view` and each round's comment on the PR (on a
repository that is not owned, its `comment.md`). Never run a
review round yourself, and never send the pane a round it did not ask
for.

## 6. Ratification

Only this skill declares the loop clean or converged, and only on its
own evidence. When the pane stops, verify every item below. The
newest round directory is
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/`.

1. **The reviewed head is the PR's head.** `range.head` in the newest
   `round.json` equals `headRefOid` from
   `gh pr view <n> --json headRefOid`.
2. **The newest round reviewed the whole PR.** `range.review_scope`
   starts with `full:`. A `delta`, `none:`, partial, nothing reviewable
   or unrecovered round declares nothing.
3. **The round's comment is on the PR** with the same round number and
   verdict as `round.json`. On a repository that is not owned
   (pr-review §8), check `comment.md` in the round directory instead,
   and `scan.sh <comment.md>` exits 0: the round does not post it.
4. **The gate is green on the PR's code, not your checkout.** Run it in
   the implementer's worktree (`workmux path <handle>` prints it), after
   verifying the worktree's HEAD equals the PR's headRefOid
   (`git -C <worktree> rev-parse HEAD`). A green gate on any other tree
   declares nothing. Use the intake gate words as written. The exit code
   decides green; read the log for what pr-review §4 names (skipped,
   deselected, or deleted tests).
5. **Every Rejected and Accepted disposition holds.** Read the
   Dispositions blocks of every round comment. On a repository that is
   not owned, read them from each round directory's `comment.md`.
   Check each reason
   against the diff. The author of the code wrote these reasons, so
   this audit is the loop's independent check.

Then decide:

- All five hold and the newest round (a clean round 1 or the
  convergence round) is `No issues found.`: the
  loop ends `clean`.
- All five hold and the convergence round is `converged (all blocking
  findings low and dispositioned).`: the loop ends `converged`, with the
  accepted judgment calls listed in the final report.
- The loop ends `clean` or `converged`, and
  `gh pr view <n> --json isDraft -q .isDraft` prints `true`: mark the
  PR ready with `gh pr ready <n>`. When it fails, the final report's
  Draft line carries its error, so the human marks the PR ready.
- A disposition does not hold, and refine rounds remain: send one
  refine instruction that names the finding and why the reason fails.
  The pane fixes it, then runs the convergence round again.

  ```bash
  workmux send <handle> "Refine round <k> on PR <n>: the orchestrator overrules <finding>: <reason>. Run the pr-refine skill on it, then the convergence round."
  ```

  `<k>` is the count of refine rounds the PR has had, plus 1, as the
  dispatch template counts them. Add nothing beyond the finding and the
  reason: no fix directions and no retry policy. `workmux send` prints
  nothing when it succeeds. Verify the delivery with
  `workmux capture <handle>`, and send again only when the capture does
  not show the instruction.

- A disposition does not hold and the cap is spent, or the pane
  stopped on `cap spent`: the loop ends `capped-unrecovered`, with the
  remaining findings quoted in the report.
- Items 1 to 4 fail: send the pane what failed (a stale head, a missing
  full-PR round, a missing comment). A second failure on the same item
  ends the loop `blocked`.

## 7. The final report

The last message of the run, verbatim to the future runner. Fill in
[`final-report-template.md`](final-report-template.md): every field
stays, also after a context compaction, and a field you cannot fill says
why.

- task ref (source locator and title), PR link, and whether the PR is
  still a draft
- verdict: `clean` (convergence round found nothing and the gate printed
  green), `converged` (blocking findings existed but the convergence
  round found every one low and dispositioned; the accepted judgment
  calls are listed), `capped-unrecovered` (blocking findings remain
  after 3 rounds), or
  `blocked` (pane death after redispatch, no gate found, scan hit, a
  `pr-round.sh` exit 4, 5, or 127, an exit 6 after the one `--rerun`, an
  exit 8 after the one retry, or a partial, nothing-reviewable or unrecovered reviewer with nothing
  from any source)
- per-round one-liners: round number, short SHA, verdict, who ran it
- the ratification: each item of step 6 and its result, and every
  disposition you overruled, with the reason
- the follow-ups from the final round's comment, verbatim: findings on
  reviewed code the loop left for the human
- the gate: the command and its final printed result
- anything a scan blocked, with the line it caught
- reviewer session ids and token totals (the newest round comment's
  Cost line: the `cumulative_tokens` its round.json carried when it was
  written; a rerun of an earlier round afterwards does not recompute
  later rounds' round.json, so say so plainly when one happened), the
  critic's tokens summed from every round comment's Cost line (on a
  repository that is not owned, each round's `comment.md`) (naming
  any round whose critic tokens were not reported), reviewer and critic
  bindings used, ocr version
- the PR comment links, one per round (on a repository that is not
  owned, the draft paths for the human to post)

Before the final message is spoken, write the report verbatim to
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md`, the same
directory that holds the round dirs. The final message remains the
report; the file is its durable copy, the exact text, no summary layer.

## Failure policies

- **Pane death or failed pane check:** redispatch once by reopening the
  surviving worktree (`workmux open <handle>`, worktree and branch
  persist), with the dispatch prompt from the template again: its
  "Resuming" section filled in when the PR exists. Second failure:
  blocked.
- **No gate found:** the round reports blocked. Never invent one.
- **Scan hit on a comment body:** do not post it. Record the finding; it
  surfaces in the final report. Unattended does not mean leaked.
- **Empty reviewer result:** handled inside the review round (retry once
  per-commit). Two empties: the round is unrecovered, never clean and
  never failing.
- **`pr-round.sh` exit 4, 5, or 127, an exit 6 after the pane's one
  `--rerun`, or an exit 8 after the pane's one retry:** the round reports blocked, with the script's stderr line
  in the final report. The `--rerun` is the pane's, once, after a dead
  run (the dispatch template's "Review rounds" section). An exit 7 is a
  live round, not a failure.
- **PR creation failed:** capture the pane's error, report blocked. Do
  not redispatch the whole task.

## Never

- Never review `HEAD` instead of the PR's range.
- Never close the issue, tick a source checkbox, or merge the PR.
- Never force-push, and never push before the round's gate is green.
- Never post a comment that failed the scan.
- Never trust an agent's self-report where a command can verify.
- Never type a branch name or a handle by hand: copy `branch-name.sh`'s
  output and `workmux status`'s window name.
- Never do the implementer's work (commit, push, file the PR) in its
  worktree.
