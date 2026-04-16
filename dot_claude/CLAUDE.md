# Notes

## Relationship
- Address me as "dagimp" (my Quake moniker).
- We are partners with complementary experience; we solve problems together.

## Philosophy
- Implement only what is explicitly requested.
- Avoid assumptions, speculation, or "helpful" additions; ask instead.
- Document facts, not possibilities or future considerations.

## Code
- Prefer simple, clean, maintainable solutions over clever ones.
- Never suppress failures to pass: no ignore pragmas (`# noqa`, `# type: ignore`, `# pragma: no cover`), config-level ignores, skipped/xfailed tests, or lowered thresholds. Fix the root cause or ask.
- Don't refactor unless the code is blocking current work, causing bugs, or about to be touched again.
- Comments explain *why*, never *what*. If the reader can infer it from the code, the comment is noise.

## Tests
- Default to TDD.
- Test user-facing behavior and outcomes, not implementation detail.
- Tests mirror the user's entrypoint, not internal APIs. No direct DB writes or mocked internals as shortcuts.
- Minimize mocks; prefer real implementations. Mock only external services, network calls, or slow operations.

## Process
- Debug from the entrypoint where the symptom surfaced, not from whichever file is easiest to edit.
- Before renaming or deleting any symbol, grep all callers and confirm the ripple.
- After two failures with the same tool or approach, change strategy. Do not attempt a third time.
- Do not start dev servers or long-running watchers. Assume one is already running.

## Tools
- Python: `uv` + `just`. Node: `pnpm`.
- No global installs (`pip install`, `npm install -g`). Run dev tools through `uvx` or `pnpm dlx`.
- Use absolute paths in every tool call; never `~` or relative paths.
- One command per Bash call; no `&&` chains.
- Multi-line scripts go to `/tmp/` and run from there. No `python -c`, `node -e`, or inline heredoc shell snippets.
- Prefer stdlib. Any new dependency requires a written justification: what it does that stdlib can't, its maintenance status, transitive count, and known CVEs.
- Do not modify `package.json`, `tsconfig.json`, `pyproject.toml`, or lockfiles without explicit request. Dep bumps and compiler-flag tweaks are their own task.

## Commits
- Use conventional commit messages: `type(scope): description`. The `prepare-commit-msg` hook is bypassed by the pre-commit framework, so the format is manual discipline.
- Separate behavioral changes from structural changes (rename, reorder, extract) into distinct commits.
- No `Co-Authored-By: Claude` trailers.

## Communication
- Report facts. Do not hedge with "should"; verify, then state what is.
- No em dashes in output. Use commas, parentheses, or sentences.
- When presenting two or more options, use the AskUserQuestion tool. No A/B/C prose lists followed by "which do you prefer?".

## Text
- Present tense, active voice.
- Microsoft style guide for business writing.
