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
comment. The caller (the implementer in the issue-to-pr loop, which
runs every round, or a human) assembles nothing by hand; this skill defines
every step.

Two independent reviews plus the caller's read is the whole point: a
single reviewer that found nothing proves only that one reader was
unpersuaded.

## 1. Run the round

The range mechanics live in the slot's tested script, not in this
skill's prose:

```bash
$HOME/.claude/skills/issue-to-pr/tools/pr-round.sh \
  --repo <checkout-dir> --pr <n> --round <N> \
  --brief <brief-file> --expect-branch <branch-name> \
  [--expect-head <pushed-sha>] [--effort low|medium|high] [--timeout <minutes>] \
  [--max-tools <n>] [--max-tokens-budget <n>] [--exclude <globs>]
```

`<checkout-dir>` is the absolute path of the local clone or worktree
that holds the PR branch. It is not the `owner/name` slug.

A round runs for 15 to 80 minutes or more, and a killed call kills the
round. The round's log goes beside the round dir, not in it, and that
directory does not exist before round 1. Create it first, on either
path below:

```bash
mkdir -p "$HOME/.cache/pr-loop/<owner/repo>/pr-<n>"
```

Use the harness's own background run when it has one that outlives the
tool call's time limit and reports the exit (Claude Code's Bash
`run_in_background`). End the command with `echo "exit=$?" >>"<log>"`.

Only when the harness has no such run (opencode's bash tool stops a
call after 120 seconds by default), start the round in a detached tmux
session. A tmux session survives the end of the tool call; a background
`&` job of the call can die with it. A tmux session gets the tmux
server's environment, not yours (a PATH without `gh` exits 127), so
pass your PATH:

```bash
tmux new-session -d -e PATH="$PATH" \
  -e LOG="$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>.log" \
  -s pr-round-<n>-<N> sh -c \
  '$HOME/.claude/skills/issue-to-pr/tools/pr-round.sh <args> >"$LOG" 2>&1; echo "exit=$?" >>"$LOG"'
```

Then poll. Each poll is one tool call with a sleep shorter than the
tool's limit (`sleep 100` under opencode's default). Either way, the
round is done when the log's last line is `exit=<code>`. While it runs,
the round dir has a `round-<N>.lock` file beside it.

`--effort` and `--timeout` go to every review run of the round. Pass
them only when the caller gives them; without them the binding's
defaults apply (ocr: `medium`, `80`). For ocr, effort sets the review
passes per file group (low 1, medium 2, high 3), and a pass after the
first runs only when the one before added a finding. ocr multiplies the
timeout by those passes, so the default gives each group 160 minutes.

`--max-tools` and `--max-tokens-budget` also go to every review run.
Without them the binding's defaults apply (ocr: `200`, `25000000`).
For ocr, `--max-tools` is the tool rounds per file group, 50 or more.
`--max-tokens-budget` caps the tokens of one ocr run, not of one group.
A group over the budget gets one final round and fails as `budget`,
and ocr starts no more groups. The binding also makes ocr review test
files and Markdown files, which ocr skips by default.

`--exclude <globs>` also goes to every review run: comma-separated,
gitignore-style globs. For ocr, they merge with the binding rule's
excludes. Without the flag, the round passes no exclude. For example, a docs-only workflow such as /doc-cleanup passes
`--exclude '**/*.md'`. When the exclude removes every changed file, the
round has no clean verdict, and the human marks that PR ready.

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
older ones gave way. A brief over the limit on its own, or one whose
assembled background overflows once the standing dispositions join it,
stops the round with exit 2 before any review runs, leaving the round
dir untouched: condense it to the
task (its asks,
the settled decisions, the constraints) and rerun, never pass a
dispatch prompt or loop instructions as the brief. In the issue-to-pr
loop, the pane stops instead: the brief is the orchestrator's to
condense. A convergence round
runs no reviewer, so it writes no `background.md` and checks no limit.

From round 2 on, `round.json` carries `range.prior_head` (the previous
round's head) and the round directory holds `delta.txt`, the
`path:start-end` hunks changed since that head. The reviewer then
reviews only the delta, from `range.reviewed_from` (the prior head) to
the PR head: a finding outside it can only be a follow-up, except a
high. High severity blocks anywhere, in the delta or out, and the
caller counts it under Findings. An empty
delta (the same head again) reviews the
whole PR from the merge base instead, never an empty range. A change
that adds or modifies no lines (a deletion) also reviews the whole PR,
with the scope `full: the change since the prior round adds no lines`
and no `delta.txt`, so every finding blocks as new.

The delta stands in for the whole PR only when the new head descends
from the prior round's head. After a rebase the round reviews the whole
PR from the merge base and writes no `delta.txt`, so every finding
blocks as new. `round.json`'s `range.review_scope` says which: `delta`,
or `full: <why>`.

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

The convergence round passes `--convergence`. It runs no reviewer and
no per-commit retry, so nothing is billed for the reviewer. The critic
and your own read review the whole PR at the head. `round.json`
records the scope `full: this is the convergence round` (the whole PR,
from the merge base to the head), empty `runs`, and
`reviewer_skipped: "convergence"`, also after a base merge.
`delta.txt` stays as the round computed it, so a finding blocks or
follows up as it did when the reviewer ran. Round 1 refuses
`--convergence` with exit 2: round 1 keeps the reviewer.

A `partial` prior round does not send the next round back to the whole
PR: the same caps re-fail the same files. Its unfinished files go to
`prior-unfinished.txt`, and `critic-input.sh` hands the critic their
whole-PR diff, where only a high finding blocks.

`--expect-branch` binds the round to this loop's branch: a PR whose
head is any other branch is a hallucinated number, and the script exits
3 before anything reviews or posts. Omit it only when the caller
cannot know the branch (a human's standalone review).

Pass `--expect-head <pushed-sha>` when the round starts right after a
push (`git rev-parse HEAD` after the push). Right after a push,
`gh pr view` can still report the previous head. The script waits up to
about a minute until GitHub reports the pushed head, then reviews only
that head. When GitHub never reports it, the script exits 8 before it
creates or changes any round evidence: run the round again once. The script
resolves the range from the PR (never the checkout's `HEAD`), fetches
the refs, runs the active reviewer binding over the round's range,
applies the per-commit
empty-retry policy once per commit in that range, and prints the round
directory
whose `round.json` carries the range, the identity, every run (mode,
directory, status, session id, exit code), and `reviewer_complete`.
The reviewer's range is `origin/<base>..<headRefOid>` in merge-base
mode on a full-scope round, and `<range.reviewed_from>..<headRefOid>`
on a delta round. After a base merge it runs from the baseline to a
commit that has the head's tree and only the baseline as parent.

The script exits 4 when the PR is missing, not open, or not
resolvable, 5 when the repository, its refs, the changed-file
listing, the gh user, or the PR comments cannot be read, and 127 when
`gh`, `jq`, or `git` is
missing. It exits 6 when the round directory already holds evidence:
`--rerun` moves that evidence into a `superseded-*/` subdirectory, then
runs the round. Pass `--rerun` only when the earlier run of this round
died and left no `round.json` (a harness timeout kills it), or when §2
sends a convergence round back to the reviewer. A round dir with a
`round.json` and a usable comment (below) is a finished round: use it.
The
script exits 7 when another live process runs the same round. Wait for
that round. Never pass `--rerun` over it: two callers on one round
overwrote each other's evidence on PRs 137 and 230.

The script exits 9 before any review when an earlier round in the PR's
round folder has a `round.json` and no usable comment. A usable comment
is a whole, scan-clean `comment.md` in that round's directory, or a
round comment of yours on the PR with that round's heading. A round
whose `round.json` is under `superseded-*/` does not count. The stderr
line names the round, and the round dir holds no evidence. In the
issue-to-pr loop, the pane stops with
`blocked: round <N> has no comment`.

## 2. Read round.json

**`range.review_scope` starting with `none:`** is a base merge with no
PR change. Skip steps 3 to 5: no source runs. Post a comment per
report-template.md with the verdict line its list gives for a `none:`
scope and the round dir's `prior-findings.md`, verbatim, as its
`**Findings:**` section when the file exists. The
prior round's blocking findings then stand for /pr-refine and for the
next round.

**`reviewer_skipped: "convergence"`** is a convergence round: no
reviewer ran, by design. Steps 3 to 5 run as usual. The round is clean
when the critic ran and neither the critic nor your read has a blocking
finding. It is not partial and not unrecovered: the shapes below do not
apply to it. When `critic-input.sh` exits 2, fix it as §3 says and run
it again. Any other non-zero exit leaves the round with no
critic, and the round posts nothing. On exit 4 with `range.head` equal
to `range.prior_head`, run the round again with `--rerun` and without
`--convergence`: the reviewer then reviews the whole PR. In every other
case, stop with
`blocked: the convergence round has no critic: <the script's stderr line>`.

**`reviewer_complete: true`** with zero findings is a clean review:
report it as clean. **`reviewer_complete: false`** takes one of three
shapes, read from `runs[].status`:

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

The round's cost is a fact the comment carries: `round.json`'s
`cumulative_tokens` becomes the template's Cost line, so a reader can
see what the loop has spent to date. The critic's tokens are not in
`round.json` (the critic is a subagent, not the reviewer binding): take
them from the usage the harness reports when the subagent returns, and
put them on the Cost line beside the reviewer's. opencode's task tool
reports no usage, but its result starts with `<task id="ses_...">`, and
the opencode database holds that session's tokens:

```bash
sqlite3 -readonly "file:$HOME/.local/share/opencode/opencode.db?mode=ro" \
  "select tokens_input + tokens_output + tokens_reasoning + tokens_cache_read + tokens_cache_write from session where id = '<ses_id>'"
```

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
  --repo <checkout-dir> --round-dir <round-dir> --brief <brief-file>
```

When the script exits 2, fix the cause and run it again: the call, a
missing `critic-prompt.md` (its stderr line names it), or a missing
`round.json` (it prints only its usage line; run the round first).
When it exits 4 (the prompt is over 200,000 bytes and
cannot pass inline), 5 (the diff failed) or 127 (a dependency is
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
critic's output. Then check:

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
  from ever converging (measured on PR 40: 24 of 32 findings in rounds
  3 to 6 sat on reviewed code). Follow-ups are listed, never fixed in
  the loop and never dispositioned; the final report hands them to the
  human.
- **Follow-up, also when `new`:** a low finding on test assertions or
  on code-comment wording that the previous refine round added. Each
  refine that pins one assertion or rewords one comment gives the next
  critic a new low to flag (PRs 217, 607, 616: the refine cap spent on
  one test's assertions or one comment's wording). A medium or high
  finding there still blocks: a test that does not pin its fix is a
  real defect.

## 6. Assemble the comment

Follow [`report-template.md`](report-template.md) exactly: marker first
line, heading, verdict, visible consolidated findings tagged by source,
collapsed blocks with each source's output verbatim. When two sources
report one gap, list it once with both tags (`[reviewer, critic]`), and
the verdict counts it once. The reviewer's
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

- Never review `HEAD` or the checkout's branch tip.
- Never soften or summarize the binding's rendered output; verbatim or
  not at all.
- Never post a comment that failed the scan.
- Never report an empty result as clean or as a failure.
- Never write, wrap, or prefix the critic's input, also after a context
  compaction: the prompt is §3's one instruction, and the input is
  `critic-input.sh`'s output and nothing else.
- Never run two rounds of one PR at the same time.
