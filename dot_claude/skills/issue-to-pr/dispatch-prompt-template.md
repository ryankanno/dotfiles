# Task: <title>

## The brief

<body of the brief file, verbatim>

Source: <source locator>

Brief file: `<absolute path of the brief file>`

<Only when the grill is on; omit this section entirely when it is off:>
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
Every round has a unique number, and every round posts its comment.

1. **Round 1:** right after the PR is filed, run the pr-review skill on
   the PR, with `--expect-branch <branch-name>` and
   `--expect-head <the SHA you pushed>` (`git rev-parse HEAD`).
2. **Refine rounds:** while the newest round has blocking findings, run
   the pr-refine skill on the PR. Refine round k writes review round
   k+1. Run at most 3 refine rounds.
3. **The convergence round:** after a refine round, when the newest
   round is `No issues found.` or a converged candidate, run the
   pr-review skill once more on the same head, and pass `--convergence`
   to `pr-round.sh`. It takes the next free round number. A blocking
   finding in it sends you back to step 2 while refine rounds remain.
   A clean round 1 needs no convergence round: it already reviewed the
   whole PR at this head.
4. **Stop** and report one stop state: `clean` (after a clean round 1
   or the convergence round), `converged candidate` (after the
   convergence round), `cap spent`, or `blocked: <reason>`.

Every review round passes `--brief <the brief file above>` to
`pr-round.sh` and `critic-input.sh`.

A round runs longer than one tool call. Start it in the background as
pr-review §1 says. When `pr-round.sh` exits 6 and the round dir has no
`round.json`, your earlier run of that round died: pass `--rerun` once.
When it exits 7, another process runs that round: wait for it, and
never `--rerun` over it. When it exits 8, GitHub did not report the
pushed head in time, and the round left no evidence: run it again
once, without `--rerun`. A second exit 8 stops the loop as blocked.

After you stop, a refine instruction can arrive by `workmux send`. It
names a disposition the orchestrator overrules. Run the pr-refine skill
on that finding, then the convergence round again, then stop.
<only when intake set the reviewer's effort, timeout, tool cap or token
budget; omit this line otherwise, and keep only the flags intake set:>
Every review round passes `--effort <level> --timeout <minutes>
--max-tools <n> --max-tokens-budget <n>` to `pr-round.sh`.

## When you are done

Finish with two lines as your last message, and nothing else: the PR
URL, then `Stop: <stop state>`. The orchestrator verifies both on its
own.
