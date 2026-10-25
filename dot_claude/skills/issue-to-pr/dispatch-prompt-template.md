# Task: <title>

## The brief

<body of the brief file, verbatim>

Source: <source locator>

Brief file: `<absolute path of the brief file>`

<Only when the PR already exists (a resume, or a redispatch after pane
death); omit this section otherwise:>
## Resuming PR <n>

PR <n> (<PR URL>) already exists on this branch. Do not file another
PR, and do not redo work the branch already holds.

- Read the newest round directory under
  `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/`. When there is none,
  start at Round 1 below.
- A round with a `round.json` and a usable comment (`round-comment.sh`
  prints it) is finished: continue the "Review rounds" loop below from
  it, with the next free round number. A round with a `round.json` and
  no usable comment is unfinished: continue it from pr-review §2. Do not run `pr-round.sh`
  again, except for the `--rerun` that pr-review §2 names after a
  convergence round's `critic-input.sh` exit 4. Any other round is unfinished: finish that same
  round with the pr-review skill, by the exit 6 and exit 7 rules below.
- The PR has had <refine count> refine rounds. Count them against the
  cap of 3 refine rounds below. Do not get the count from the round
  numbers: a convergence round takes a round number of its own.
<or, only when the PR has no rounds.txt, in place of the bullet above:>
- The PR's refine-round count is unknown. Run at most 1 more refine
  round.
<omit this bullet when the PR has no rounds.txt:>
- The newest finished round <was | was not> a convergence round. When
  it was a convergence round with no blocking finding, do not run
  another convergence round: stop, and report its stop state.
<only when the prior run left a final report:>
- The prior run's final report is `<path of final-report.md>`: its
  verdict and remaining findings carry forward.

<Only when the grill is on and no PR exists yet; omit this section
entirely otherwise:>
## Before any code: plan, then grill it here

1. Write the implementation plan (the writing-plans skill).
2. Run the grill-me skill on that plan with the human, in this window.
   Ask each open decision with the AskUserQuestion tool, in terms of what
   a user sees, and render options where the question is visual. Every
   decision the brief leaves open is a branch to walk.
3. Before writing code, verify: restate every decision as the human
   answered it, and get a yes. Write the agreed decisions into the spec
   or plan the change ships with.
4. Only then start the work below. Do not ask the human anything after
   this point unless a fact contradicts a decision they made; say so
   plainly when it does.

## How to work

- Work test-first: write the failing test that mirrors the user-facing
  entrypoint, then the code that passes it. Minimize mocks; mock only
  external services. Do not suppress failures to pass: no ignore pragmas,
  no skipped tests, no lowered thresholds. Fix the root cause.
- Run the gate before every push, once per push. Use these words as
  written, with no added flags. Judge the gate by its exit code, not by
  a summary line in its output:

  ```
  <gate command> >"<log file>" 2>&1; echo "gate exit=$?"
  ```

  Read only the log's tail, and only when the exit is not 0. The exit
  code decides whether you push. A review round's own read still
  scrutinizes the whole log (pr-review §4).

- When the repository has `.pre-commit-config.yaml`, run
  `uvx pre-commit run --files <staged files>` before each commit. Fix
  every failure before the commit. For example, a shellcheck warning in
  a staged `tests/*.sh` file stops that commit.
- Commit conventionally, `type(scope): description`. Behavioral and
  structural changes land in separate commits. No attribution trailers.
- Push and file the PR:

  ```
  git push -u origin HEAD
  gh pr create --draft <--assignee @me only when the gh user is an admin of the repository; omit it otherwise> --title "<title>" --body-file <body file>
  ```

  Keep the PR a draft. A repository that auto-merges on green CI
  merges a ready PR before its review rounds finish. The orchestrator
  marks it ready when the loop ends clean or converged.

  Write the body to a file outside the worktree first (`mktemp`): an
  inline `--body` breaks on the quotes and backticks a multi-line body
  holds, and a body file inside the worktree can be committed. The PR
  body carries `Closes #<n>` <only for gh issue sources; omit this
  line entirely for markdown or HTML sources>.
- Never force-push.
- If an open PR already exists on this branch, do not create another:
  verify it with `gh pr view` and continue the work on it.

## Review rounds: you run every one

The orchestrator runs no review. It ratifies your rounds when you stop.
Every round has a unique number, and every round posts its comment per
pr-review §8: on a repository that is not owned, the comment stays a
draft in the round directory.
Before you start a round, add one line to `rounds.txt` in the PR's
round folder, the folder that holds `round-<N>/` (make it as
pr-review §1 says when it is missing): `<N> review` (round 1), `<N> refine` (a pr-refine run), or
`<N> convergence`. A resume reads the refine count from this file. A
rerun of a round adds no line.

1. **Round 1:** right after the PR is filed, run the pr-review skill on
   the PR, with `--expect-branch <branch-name>` and
   `--expect-head <the SHA you pushed>` (`git rev-parse HEAD`).
2. **Refine rounds:** while the newest round has blocking findings, run
   the pr-refine skill on the PR. Refine round k writes review round
   k+1. Run at most 3 refine rounds. Before you start each refine
   round, check that the PR is `OPEN`
   (`gh pr view <n> --json state -q .state`). When it is not, stop with
   `blocked: PR <n> is <state>`.
3. **The convergence round:** after a refine round, when the newest
   round is `No issues found.` or a converged candidate, run the
   pr-review skill once more on the same head, and pass `--convergence`
   to `pr-round.sh`. It takes the next free round number. The round
   runs no reviewer: the critic and your read review the whole PR at
   this head. A blocking
   finding in it sends you back to step 2 while refine rounds remain.
   A clean round 1 needs no convergence round: it already reviewed the
   whole PR at this head. When pr-review §2 leaves the round with no
   critic and does not send it back to the reviewer with `--rerun`,
   stop with
   `blocked: the convergence round has no critic: <the script's stderr line>`.
4. **Stop** and report one stop state: `clean` (after a clean round 1
   or the convergence round), `converged candidate` (after the
   convergence round), `cap spent`, or `blocked: <reason>`.

Every review round passes `--brief <the brief file above>` to
`pr-round.sh` and `critic-input.sh`.

A round runs longer than one tool call. Start it in the background as
pr-review §1 says. Then act on the exit code of `pr-round.sh`. A
`<stderr line>` is the script's last stderr line, verbatim: scan hits or
a passed-over `comment.md` can come above it. When the script printed
no stderr line, stop with the exit code alone.

| Exit | What it means | What you do |
|---|---|---|
| 0 | The round ran. | Continue the round with pr-review §2. |
| 2 | A usage error, an unusable environment, a brief over the reviewer's background limit, or a `refine-dispositions.md` that fails the scan. | Stop with `blocked: pr-round.sh exit 2: <stderr line>`. |
| 3 | An identity mismatch: the PR head is not this loop's branch. | Stop with `blocked: identity mismatch: <stderr line>`. |
| 4 | The PR is missing, not open, or not resolvable. | Stop with `blocked: pr-round.sh exit 4: <stderr line>`. |
| 5 | The repository, its refs, the changed-file listing, the gh user, or the PR comments could not be read. | Stop with `blocked: pr-round.sh exit 5: <stderr line>`. |
| 6 | The round dir already holds evidence. | When it has no `round.json`, your earlier run of that round died: pass `--rerun` once. On an exit 6 after that `--rerun`, stop with `blocked: pr-round.sh exit 6: <stderr line>`. When it has a `round.json` and a usable comment, the round is finished: continue the loop from it. When it has a `round.json` and no usable comment, finish it from pr-review §2, with the one `--rerun` §2 names after a convergence round's `critic-input.sh` exit 4. |
| 7 | Another process runs that round. | Wait for it. Never `--rerun` over it. |
| 8 | GitHub did not report the pushed head in time, and the round left no evidence. | Run the round again once, without `--rerun`. On a second exit 8, stop with `blocked: pr-round.sh exit 8: <stderr line>`. |
| 9 | An earlier round has no comment on disk or on the PR. | Stop with `blocked: round <N> has no comment`, with the round its stderr line names. |
| 127 | A dependency is missing. | Stop with `blocked: pr-round.sh exit 127: <stderr line>`. |
| Any other | A failure the table does not list. | Stop with `blocked: pr-round.sh exit <code>: <stderr line>`. |

After you stop, a refine instruction can arrive by `workmux send`. It
names a disposition the orchestrator overrules. Run the pr-refine skill
on that finding, then the convergence round again, then stop.
<only when intake set the reviewer's effort, timeout, tool cap, token
budget or exclude; omit this line otherwise, and keep only the flags
intake set:>
Every review round passes `--effort <level> --timeout <minutes>
--max-tools <n> --max-tokens-budget <n> --exclude '<globs>'` to
`pr-round.sh`.

## When you are done

Finish with two lines as your last message, and nothing else: the PR
URL, then `Stop: <stop state>`. The orchestrator verifies both on its
own.
