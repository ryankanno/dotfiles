# Conventional Commit Message Generator

**Command:** `/project:do-conventional-commit-message`

You are an autonomous programming agent tasked with analyzing the current repository state and generating a conventional commit message based on staged or unstaged changes.

## Available Tools
```bash
git status              # Check current repository state
git diff --staged       # Review staged changes
git diff               # Review unstaged changes (if index is dirty)
git log --oneline -1   # Check latest commit for context
```

## Workflow

1. **Analyze Repository State**
   * Run `git status` to understand current state
   * Check if there are staged changes with `git diff --staged`
   * If nothing is staged but working directory is dirty, analyze unstaged changes with `git diff`
   * If neither staged nor unstaged changes exist, report "No changes to analyze"

2. **Review Changes**
   * Examine the diff output to understand:
     * Which files were modified, added, or deleted
     * The nature of the changes (new features, bug fixes, refactoring, etc.)
     * The scope and impact of modifications
   * Look at file patterns and extensions to determine context

3. **Determine Conventional Commit Type**
   * Analyze the changes to select the most appropriate type:
     * `feat:` - New features, functionality, or capabilities
     * `fix:` - Bug fixes, error corrections, issue resolutions
     * `docs:` - Documentation-only changes (README, comments, etc.)
     * `style:` - Code formatting, whitespace, semicolons (no logic changes)
     * `refactor:` - Code restructuring without changing external behavior
     * `perf:` - Performance improvements and optimizations
     * `test:` - Adding, updating, or fixing tests
     * `chore:` - Maintenance, dependency updates, tooling changes
     * `ci:` - CI/CD pipeline, workflow, or automation changes
     * `build:` - Build system, package.json, webpack, etc.
     * `revert:` - Reverting previous commits

4. **Generate Commit Message**
   * Format: `<type>(<scope>): <description>`
   * Scope is optional but recommended for larger projects
   * Description should be:
     * Concise (50 characters or less preferred)
     * Written in imperative mood ("add" not "added")
     * Lowercase first letter
     * No ending period
     * Descriptive of what the change accomplishes

5. **Output Result**
   * Display the generated conventional commit message
   * Provide brief explanation of why this type and description were chosen
   * Show which changes influenced the decision

## Conventional Commit Type Selection Logic

**File-based heuristics:**
* New files in `src/`, `lib/`, `app/` → likely `feat:`
* Changes to `README.md`, `docs/`, `*.md` → likely `docs:`
* Changes to `package.json`, `requirements.txt`, `Cargo.toml` → likely `chore:`
* Changes to `.github/workflows/`, `Jenkinsfile`, `.travis.yml` → likely `ci:`
* Changes to `webpack.config.js`, `tsconfig.json`, `Makefile` → likely `build:`
* Changes to `test/`, `spec/`, `*_test.py`, `*.test.js` → likely `test:`

**Content-based heuristics:**
* Added functions/classes/methods → likely `feat:`
* Bug fix patterns (try/catch, error handling, null checks) → likely `fix:`
* Renamed variables, extracted functions (no behavior change) → likely `refactor:`
* Added caching, optimized algorithms → likely `perf:`
* Only whitespace, formatting changes → likely `style:`

## Example Outputs

```bash
# Feature addition
feat(auth): add OAuth2 login integration

# Bug fix
fix(api): handle null response from user service

# Documentation update
docs: update installation instructions in README

# Refactoring
refactor(utils): extract validation logic to separate module

# Performance improvement
perf(database): optimize user query with indexing

# Test addition
test(auth): add unit tests for login validation

# Maintenance
chore: update dependencies to latest versions

# Build system
build: configure webpack for production builds

# CI/CD
ci: add automated testing workflow
```

## Scope Guidelines

Common scopes to consider:
* **Component/Module names:** `auth`, `api`, `database`, `ui`, `utils`
* **Feature areas:** `login`, `dashboard`, `profile`, `settings`
* **File types:** `css`, `html`, `js`, `py`, `rs`
* **Directories:** `frontend`, `backend`, `mobile`, `web`

## Edge Cases

* **Multiple types of changes:** Choose the most significant change type
* **Breaking changes:** Add `!` after type: `feat!: redesign user API`
* **Mixed scope changes:** Use broader scope or omit scope
* **Unclear changes:** Default to `chore:` with descriptive message
* **Large refactoring:** Consider `refactor:` even if it spans multiple areas

## Error Handling

* If no changes detected: "No changes to analyze for commit message"
* If changes are too complex to categorize: Default to `chore:` with generic description
* If unable to read git status: Report git error and suggest manual inspection

## Success Criteria

* Generated message follows conventional commit format exactly
* Commit type accurately reflects the primary nature of changes
* Description is clear, concise, and uses imperative mood
* Scope (if used) is relevant and helpful
* Message provides value for project history and changelog generation
