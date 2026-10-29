---
name: pr-review
description: >-
  Use when asked to run one native review round on a pull request and post
  it as a comment: "run a review round", or as a step of the issue-to-pr
  loop. Runs the reviewer binding (ocr by default) and the adversarial
  critic over the PR's ref range, adds the caller's own read, and posts
  the standard report comment. Not for fixing findings (/pr-refine) and
  not for the whole loop (/issue-to-pr). Not for a quick or general code
  review of a PR (/code-review).
---

# pr-review

One review round over a pull request's ref range: the reviewer binding,
the adversarial critic binding, the caller's own read, one report
comment. The caller (the implementer in the issue-to-pr loop, which
runs every round, or a human) assembles nothing by hand; this skill defines
every step.

Two independent reviews plus the caller's read is the whole point: a
single reviewer that found nothing proves only that one reader was
unpersuaded.

## 1. Run the round

```bash
$HOME/.claude/skills/issue-to-pr/tools/pr-round.sh \
  --repo <checkout-dir> --pr <n> --round <N> \
  --brief <brief-file> --expect-branch <branch-name> \
  [--expect-head <pushed-sha>] [--effort low|medium|high] [--timeout <minutes>] \
  [--max-tools <n>] [--max-tokens-budget <n>] [--concurrency <n>] \
  [--exclude <globs>]
```

`<checkout-dir>` is the absolute path of the local clone or worktree
that holds the PR branch. It is not the `owner/name` slug.

A round runs for 15 to 80 minutes or more, and a killed call kills the
round. The round's log goes beside the round dir, not in it, and that
directory does not exist before round 1. Create it first:

```bash
mkdir -p "$HOME/.cache/pr-loop/<owner/repo>/pr-<n>"
```

Use the harness's own background run when it has one that outlives the
tool call's time limit and reports the exit (Claude Code's Bash
`run_in_background`). End the command with `echo "exit=$?" >>"<log>"`,
with `<log>` the file
`$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>.log`.
Only when the harness has no such run, read
[`background-run.md`](background-run.md) and start the round in a
detached tmux session. Either way, the
round is done when the log's last line is `exit=<code>`. While it runs,
the round dir has a `round-<N>.lock` file beside it.

`--effort`, `--timeout`, `--max-tools`, `--max-tokens-budget`,
`--concurrency` and `--exclude` go to every review run of the round.
Pass them only when the caller gives them; without them the binding's
defaults apply, and the round passes no exclude. The active reviewer
binding's header gives their meaning and defaults:
`$HOME/.claude/skills/issue-to-pr/tools/<reviewer>/review.sh`, with the
manifest's `reviewer` (ocr). When the exclude removes every changed
file, the round has no clean verdict, and the human marks that PR
ready.

The reviewer reads only its background file, never the PR comments, so
the script joins the brief with every Rejected and Accepted line from
the Dispositions blocks of this loop's own round comments (marker on
line 1, your own author) into `background.md` in the round directory.
Fixed lines stay out: a fix the reviewer still flags is a fix to
re-check. `--dispositions <file>` replaces the lines read from the
comments with the file's content.

A refine round writes its own Dispositions lines to
`refine-dispositions.md` in the round directory before the round runs
(pr-refine §6). The script adds its Rejected and Accepted lines to the
lines from the comments or from `--dispositions`, for `background.md`
and for the critic's `settled.md`.
A file that fails the scan stops the round with exit 2 before any
review runs. Fix what its stderr line names, then run the round again.
In the issue-to-pr loop, the pane stops instead, by the exit-code table
in the dispatch template's "Review rounds" section.
The file is not evidence of an earlier run, and `--rerun`
does not move it.

The background has a size limit: the manifest's
`reviewer_background_limit` (8000 characters for ocr, which aborts on
anything longer before it reviews a line). ocr also warns when the
background is over 2000 characters, and the loop accepts the warning:
a shorter background drops the brief's asks and the standing
dispositions, and a reviewer without the dispositions re-flags settled
findings. The dispositions fill the
room the brief leaves, newest first, and the background says how many
older ones gave way. A brief that overflows the limit stops the round
with exit 2 ([`exits.md`](exits.md)).

From round 2 on, the reviewer reviews only the delta since the prior
round's head when it can. `round.json`'s `range.review_scope` says
which: `delta`, `full: <why>`, or `none: <why>`. High severity blocks
anywhere, in the delta or out, and the caller counts it under Findings.
Read [`ranges.md`](ranges.md) when a round's scope is not `full: round 1`
or `delta`, or when it follows a `partial` round.

The convergence round passes `--convergence`. It runs no reviewer. The
critic and your own read review the whole PR at the head. Round 1
refuses `--convergence` with exit 2: round 1 keeps the reviewer.

`--expect-branch` binds the round to this loop's branch: a PR whose
head is any other branch is a hallucinated number, and the script exits
3 before anything reviews or posts. A PR whose head is on a fork exits
3 too, also when its branch name matches. Omit it only when the caller
cannot know the branch (a human's standalone review).

Pass `--expect-head <pushed-sha>` when the round starts right after a
push (`git rev-parse HEAD` after the push). Right after a push,
`gh pr view` can still report the previous head. The script waits up to
about a minute until GitHub reports the pushed head, then reviews only
that head. The script
resolves the range from the PR (never the checkout's `HEAD`), fetches
the refs, runs the active reviewer binding over the round's range,
applies the per-commit
empty-retry policy once per commit in that range, and prints the round
directory
whose `round.json` carries the range, the identity, every run (mode,
directory, status, session id, exit code), and `reviewer_complete`.

When the script exits other than 0, 3 or 7, read [`exits.md`](exits.md).
The script exits 7 when another live process runs the same round. Wait for
that round. Never pass `--rerun` over it: `--rerun` moves the live
round's evidence away while it writes. Start no other round of the PR
while one runs: the lock holds one round only, and a later round finds
no prior head on record and reviews the whole PR.

## 2. Read round.json

**`range.review_scope` starting with `none:`** is a base merge with no
PR change: follow [`ranges.md`](ranges.md)'s "A base merge" section,
which skips steps 3 to 5.

**`reviewer_skipped: "convergence"`** is a convergence round: no
reviewer ran, by design. Steps 3 to 5 run as usual. The round is clean
when the critic ran and neither the critic nor your read has a blocking
finding. It is not partial and not unrecovered: the reviewer shapes in
[`ranges.md`](ranges.md)'s "A reviewer that did not finish" section do
not apply to it. When `critic-input.sh` exits 2, fix it as §3 says and run
it again. Any other non-zero exit leaves the round with no
critic, and the round posts nothing. On exit 4 with `range.head` equal
to `range.prior_head`, run the round again with `--rerun` and without
`--convergence`: the reviewer then reviews the whole PR. In every other
case, stop with
`blocked: the convergence round has no critic: <the script's stderr line>`.

**`reviewer_complete: true`** with zero findings is a clean review:
report it as clean. **`reviewer_complete: false`** is a partial,
nothing reviewable, or unrecovered reviewer: read
[`ranges.md`](ranges.md)'s "A reviewer that did not finish" section.

The round's cost is a fact the comment carries: `round.json`'s
`cumulative_tokens` becomes the template's Cost line, so a reader can
see what the loop has spent to date. The critic's tokens are not in
`round.json` (the critic is a subagent, not the reviewer binding): take
them from the usage the harness reports when the subagent returns, and
put them on the Cost line beside the reviewer's. Under opencode, read
[`opencode-tokens.md`](opencode-tokens.md).

When neither source has a number, the line says so; a guessed number is
never written.

## 3. The adversarial critic

Resolve the critic from the manifest and follow its binding file
(`$HOME/.claude/skills/issue-to-pr/tools/<critic>/binding.md`) for how to
spawn it: a fresh, clean-context subagent whose prompt is one
instruction: read `<round-dir>/critic-input.md` in full and follow it.
`critic-input.sh` writes that file. Never write the critic's input
yourself: the script carries the instructions, the brief, the findings
this round's diff answers, the settled dispositions, and the one diff,
and leaves out the follow-ups.

```bash
$HOME/.claude/skills/issue-to-pr/tools/subagent/critic-input.sh \
  --repo <checkout-dir> --round-dir <round-dir> --brief <brief-file> >/dev/null
```

When the script exits 2, fix the cause and run it again: the call, a
missing `critic-prompt.md` (its stderr line names it), or a missing
`round.json` (it prints only its usage line; run the round first).
When it exits 4 (the prompt is over 200,000 bytes), 5 (the diff failed) or 127 (a dependency is
missing), it prints no prompt. The round runs with no critic. The
Critic block records the gap with the script's stderr line. A
convergence round follows §2 instead.

Its findings arrive numbered with file, line, the claim, the input or
state that reaches it, the harm, severity, and how it checked. Findings
that do not reference that diff are dropped, per the binding's
contract. Its "Unconfirmed candidates" section stays verbatim in the
collapsed Critic block and never enters the Findings or Follow-ups
lists: an unconfirmed candidate is not a finding.

## 4. The caller's own read

Read the diff against the brief yourself. Start with a defect pass
over the diff against the brief, before you open the reviewer's and the
critic's output. Do it before §3 spawns the critic. Then check:

- **Scope creep:** anything the diff changes that the brief does not
  ask for.
- **Weakened tests:** assertions that would survive deleting the
  feature, tests weakened to pass, tests deleted. A deleted test is a
  high-severity finding.
- **Gate output:** in refine and convergence rounds, scrutinize the
  gate transcript (the whole log file the gate line writes), not its
  exit code alone.
- **Corroboration:** agreement between two sources counts only when
  both could see the code the claim is about. A factual dispute
  settles against the code, not by counting sources.
- **Same head:** if this round runs over the same head as the prior
  round, cite new evidence against that verdict or defer to it.

## 5. Blocking or follow-up

Classify every finding from every source against the round's delta:

```bash
$HOME/.claude/skills/issue-to-pr/tools/finding-scope.sh <round-dir> <path>:<start>[-<end>]
```

- **Blocking:** high severity anywhere, or `new`: on a line changed
  since the prior round's head. Every finding in round 1 and every
  finding without a line prints `new`.
- **Follow-up:** medium or low, and `reviewed`: on code an earlier
  round already reviewed. Fresh-context reviewers find new edge cases
  in reviewed code every round, so letting those block keeps the loop
  from ever converging. Follow-ups are listed, never fixed in
  the loop and never dispositioned; the final report hands them to the
  human.
- **Follow-up, also when `new`:** a low finding on test assertions or
  on code-comment wording that the previous refine round added. Each
  refine that pins one assertion or rewords one comment gives the next
  critic a new low to flag, so those lows would spend the refine cap.
  A medium or high
  finding there still blocks: a test that does not pin its fix is a
  real defect.

## 6. Assemble the comment

Follow [`report-template.md`](report-template.md) exactly: marker first
line, heading, verdict, visible consolidated findings tagged by source,
collapsed blocks with each source's output verbatim. When more than one
source reports one gap, list it once with each source's tag
(`[reviewer, critic]`), and the verdict counts it once. The line keeps
the highest severity, and it blocks when any report blocks. It cites the `file:line` of a report
that blocks. The reviewer's
sections render with the binding's renderer, once per run recorded in
`round.json` (`render.sh <runs[].dir>`), completed or skipped alike:
thin coverage and a skipped run must read as what they are. A
convergence round has no runs: its Reviewer details block holds the
line `No reviewer ran: the convergence round runs none by design.`

The verdict line is machine-read by /pr-refine: write it exactly as one
of the lines in report-template.md's verdict list, under the condition
the list gives that line.

## 7. Scan before posting

Write the body to `<round-dir>/comment.md`, never inline and never to a
scratchpad. The next round and pr-refine read this file before the PR,
so a refine does not wait for the post. Scan it before it leaves the
machine:

```bash
$HOME/.claude/skills/issue-to-pr/tools/scan.sh <file>
```

The script rewrites home paths to `~` in place. Exit 0: post the file.
Exit 1: it printed each remaining hit (another home path, a temp path,
or a token); **do not post**. Record the lines. Exit 2: a usage
error, or the scan itself failed; **do not post**. Record its stderr.
In an interactive round, show the lines and wait instead.
Unattended does not mean
leaked; the blocked post surfaces in the loop's final report.

## 8. Post

Post only on a repository the human owns. Read the owner of the PR's
repository and the gh login:

```bash
gh repo view <owner/repo> --json owner --jq .owner.login
gh api user --jq .login
```

The repository is owned when its owner is the gh login or an org on
this list. Owned orgs: `i9-io`.

On an owned repository, post the file:

```bash
gh pr comment <n> --body-file <round-dir>/comment.md
```

Record the comment URL and the round directory: the final report needs
the session ids and token totals from the round's `round.json`
(`runs[].session_id` and `cumulative_tokens`).

On any other repository, do not post. `<round-dir>/comment.md` stays
as the draft. When the §7 scan exited 0, report to the caller that the
comment is a draft for the human to post, with its path. Otherwise
report the scan's hits, as §7 says. Record the round directory.

## Never

- Never soften or summarize the binding's rendered output; verbatim or
  not at all.
- Never write, wrap, or prefix the critic's input, also after a context
  compaction: the prompt is §3's one instruction, and the input is
  `critic-input.sh`'s output and nothing else.
