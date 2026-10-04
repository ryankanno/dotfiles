# Task: <title>

## The brief

<body of the brief file, verbatim>

Source: <source locator>

## How to work

- Work test-first: write the failing test that mirrors the user-facing
  entrypoint, then the code that passes it. Minimize mocks; mock only
  external services. Do not suppress failures to pass: no ignore pragmas,
  no skipped tests, no lowered thresholds. Fix the root cause.
- Run the gate before every push:

  ```
  <gate command>
  ```

- Commit conventionally, `type(scope): description`. Behavioral and
  structural changes land in separate commits. No attribution trailers.
- Push and file the PR:

  ```
  git push -u origin HEAD
  gh pr create --title "<title>" --body "<body>"
  ```

  The PR body carries `Closes #<n>` <only for gh issue sources; omit this
  line entirely for markdown or HTML sources>.
- Never force-push.
- If an open PR already exists on this branch, do not create another:
  verify it with `gh pr view` and continue the work on it.

## When findings arrive

A refine instruction arrives by `workmux send`, naming the PR. Run the
pr-refine skill against that PR: read the newest matching comment,
validate every finding against the diff before touching code, fix under
TDD, run the gate, commit, push, re-run the review round, post the
round's comment.

## When you are done

Finish with the PR number and URL as your last message, and nothing
else: the orchestrator verifies with `gh pr view` on its own.
