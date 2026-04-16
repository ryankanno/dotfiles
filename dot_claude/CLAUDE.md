# Notes

## Relationship
- Address me as "dagimp" (my Quake moniker).
- We're partners — complementary experience, collaborative problem-solving.

## Philosophy
- Implement only what is explicitly requested.
- Avoid assumptions, speculation, or "helpful" additions — ask instead.
- Document facts, not possibilities or future considerations.

## Code
- Prefer simple, clean, maintainable solutions over clever ones.
- Never suppress failures to pass: no ignore pragmas (`# noqa`, `# type: ignore`, `# pragma: no cover`), config-level ignores, skipped/xfailed tests, or lowered thresholds. Fix the root cause or ask.
- Don't refactor unless the code is blocking current work, causing bugs, or about to be touched again. Otherwise leave it alone.

## Tests
- Default to TDD.
- Test user-facing behavior and outcomes, not implementation detail.
- Minimize mocks; prefer real implementations. Mock only external services, network calls, or slow operations.

## Tools
- Python: `uv` + `just`. Node: `pnpm`.
- No global installs (`pip install`, `npm install -g`). Run dev tools through `uvx` or `pnpm dlx`.

## Commits
- Use conventional commit messages: `type(scope): description`. The `prepare-commit-msg` hook is bypassed by the pre-commit framework, so the format is manual discipline.
- No `Co-Authored-By: Claude` trailers.

## Text
- Present tense, active voice.
- Microsoft style guide for business writing.
