# Autonomous Pull Request Command

**Command:** `/project:do-pr $ARGUMENTS`

You are an autonomous programming agent tasked with creating and submitting pull requests to GitHub from the current branch state.

## Available Tools
```bash
git status                      # Check current repository state
git branch --show-current       # Get current branch name
git rev-list --count HEAD ^main # Count commits ahead of main
git log --oneline HEAD~n..HEAD  # Get commit history
git diff main...HEAD            # Compare branch changes against main
git push origin <branch>        # Push current branch to remote
gh pr create                    # Create pull request via GitHub CLI
gh pr list                      # List existing pull requests
gh repo view                    # Get repository information
gh auth status                  # Check GitHub authentication
/project:do-commit              # Create commit with conventional format
/project:do-conventional-commit-message  # Generate conventional commit messages
```

## Workflow Decision Logic
1. **Check for Uncommitted Changes**
   * Run `git status` to check for unstaged or uncommitted changes
   * If unstaged changes exist → Execute `/project:do-commit` to commit them first
   * If staged but uncommitted changes exist → Execute `/project:do-commit` to commit them
   * If working directory is clean → Continue with PR creation

2. **Determine PR Strategy**
   * Check current branch: `git branch --show-current`
   * Check if on main branch (should not create PR from main)
   * Check commits ahead of main: `git rev-list --count HEAD ^main`
   * Check if branch exists on remote: `git ls-remote origin <branch>`

   **Decision Tree:**
   - If uncommitted changes → Run `/project:do-commit` first, then continue
   - If on main branch → Error: Cannot create PR from main branch
   - If no commits ahead of main → Error: No changes to create PR for
   - If branch not on remote → Push branch first, then create PR
   - If branch exists on remote → Check for existing PR, update or create new

## Mode 1: New Pull Request
Use this mode when creating a fresh pull request from feature branch.

1. **Pre-flight Checks**
   * Check for uncommitted changes and commit them if needed:
     ```bash
     # Check status
     git status
     
     # If changes detected, commit them
     /project:do-commit "prepare changes for pull request"
     ```
   * Verify not on main branch
   * Confirm commits exist ahead of main
   * Check GitHub CLI authentication: `gh auth status`
   * Verify repository has remote origin configured

2. **Branch Analysis**
   * Run `git log --oneline HEAD~n..HEAD` to analyze commits
   * Run `git diff main...HEAD --stat` to get change summary
   * Use `/project:do-conventional-commit-message` to analyze changes and determine PR scope
   * Identify scope and type of changes for PR description

3. **Push and Create PR**
   * Push branch to remote: `git push origin <branch-name>`
   * Create PR with generated title and description
   * Set appropriate labels and reviewers if configured

## Mode 2: Update Existing Pull Request
Use this mode when PR already exists for current branch.

1. **Check for Uncommitted Changes**
   * Run `git status` to detect any uncommitted work
   * If changes found, execute `/project:do-commit` before updating PR
   * This ensures all work is included in the PR update

2. **Detect Existing PR**
   * Run `gh pr list --head <branch-name>` to check for existing PR
   * Get PR number and current status

3. **Update Strategy**
   * Push latest changes: `git push origin <branch-name>`
   * Update PR description if significant changes occurred
   * Add comment explaining updates if needed

## PR Title Generation
Use the conventional commit message directly as the PR title:

1. **Generate Conventional Commit Title**
   * Run `/project:do-conventional-commit-message` to analyze all changes in branch
   * Use the generated conventional commit message exactly as the PR title
   * No translation or conversion needed - maintain the conventional commit format

2. **Title Selection Logic**
   * Single commit: Use the existing commit message if it follows conventional format
   * Multiple commits: Use `/project:do-conventional-commit-message` to generate overall conventional commit message for all changes
   * Ensure title follows conventional commit format: `<type>(<scope>): <description>`

**Example Titles:**
```bash
# Single commit
Existing commit: "feat(auth): add OAuth2 login integration"
PR Title: "feat(auth): add OAuth2 login integration"

# Multiple commits analysis
Generated conventional message: "feat(api): add user management endpoints"
PR Title: "feat(api): add user management endpoints"

# Complex branch changes
Generated conventional message: "refactor(core): restructure authentication system"  
PR Title: "refactor(core): restructure authentication system"
```

## PR Description Template
Generate concise PR descriptions with markdown lists:

```markdown
## Changes
- [Auto-generated bullet points based on file changes and commit analysis]
- [List key modifications, new features, or fixes]
- [Include scope-specific changes if applicable]
```

**Description Generation Logic:**
1. **Use Repository Template if Available**
   * Check for `.github/pull_request_template.md` in repository
   * If template exists, use it as the base structure

2. **Fallback to Simple Description**
   * If no template exists, use the minimal format above
   * Focus on concise bullet points describing the changes
   * Keep descriptions brief and scannable

3. **Auto-populate Change List**
   * Extract key changes from `/project:do-conventional-commit-message` analysis
   * List modifications by scope or file type
   * Include any breaking changes or important notes

## Commit Analysis for PR Context
Enhanced analysis using conventional commit message generator:

1. **Impact Assessment**
   * Use conventional commit analysis to determine breaking changes
   * Count files changed: `git diff main...HEAD --name-only | wc -l`
   * Lines added/removed: `git diff main...HEAD --shortstat`
   * Breaking changes: Look for `BREAKING CHANGE:` or `!` in commit analysis

## Command Arguments
* `/project:do-pr "Custom PR title"` - Create PR with specific title (overrides conventional commit analysis)
* `/project:do-pr --draft` - Create as draft PR
* `/project:do-pr --ready` - Mark existing draft PR as ready
* `/project:do-pr --update` - Force update existing PR description
* `/project:do-pr --reviewer @username` - Add specific reviewer
* `/project:do-pr` - Auto-generate title and description using conventional commit analysis

## Output Examples

### New PR Creation with Auto-Commit
```bash
# Detecting uncommitted changes
Checking for uncommitted changes...
✓ Found unstaged changes in 3 files

Running /project:do-commit to commit changes...
✓ Created commit: feat(api): add validation middleware

# Creating new pull request
Branch: feature/user-auth (4 commits ahead of main)

Analyzing changes with conventional commits...
✓ Generated conventional commit message: "feat(auth): add user authentication system"

Pushing branch to remote...
✓ Pushed feature/user-auth to origin

Creating pull request...
✓ Created pull request #42: feat(auth): add user authentication system
  URL: https://github.com/owner/repo/pull/42

Description:
## Changes
- Add OAuth2 login integration with Google and GitHub
- Implement JWT token validation middleware
- Add user session management
- Create authentication routes and controllers
- Add validation middleware (from auto-commit)

## Testing
- Unit tests added for auth middleware
- Integration tests for login flow
- Manual testing with multiple OAuth providers

Auto-assigned labels: enhancement, security
```

### Mixed Changes with Template
```bash
# Creating pull request using repository template
Branch: feature/api-improvements (7 commits ahead of main)

Checking for uncommitted changes...
✓ Working directory clean

Found pull request template: .github/pull_request_template.md
Analyzing changes with conventional commits...
✓ Generated conventional commit message: "feat(api): improve user management endpoints"

Creating pull request...
✓ Created pull request #43: feat(api): improve user management endpoints
  URL: https://github.com/owner/repo/pull/43

Using repository template with auto-populated sections:
- Changes section filled with commit analysis
- Testing section populated with detected test files
- Related issues section ready for manual input

Auto-assigned labels: enhancement, api
```

### Existing PR Update with Auto-Commit
```bash
# Updating existing pull request
Found existing PR #42: Add user authentication system

Checking for uncommitted changes...
✓ Found staged changes in auth/middleware.js

Running /project:do-commit to commit changes...
✓ Created commit: fix(auth): handle edge case in token validation

Branch has 3 new commits since last push

Analyzing new changes...
✓ New changes: fix(auth): resolve authentication edge cases
  - 2 fix commits
  - 1 test commit
  - Impact: 4 files changed, +35 -12 lines

Pushing updates...
✓ Updated pull request #42
  Added commits:
  - fix: resolve authentication edge case
  - test: add missing auth tests
  - fix: handle edge case in token validation

PR description updated with latest conventional commit analysis.
Updated labels: enhancement, security, bug
```

## Error Handling
* If uncommitted changes fail to commit: "Failed to commit changes. Please resolve issues before creating PR."
* If on main branch: "Cannot create PR from main branch. Switch to feature branch first."
* If no commits ahead: "No changes to create PR for. Make some commits first."
* If GitHub CLI not authenticated: "Please run 'gh auth login' to authenticate with GitHub."
* If no remote origin: "No remote repository configured. Add remote origin first."
* If conventional commit analysis fails: "Warning: Could not analyze commits conventionally, using fallback PR generation."
* If branch push fails: Report git error and suggest resolution
* If PR creation fails: Report GitHub API error with suggested fixes

## Advanced Features

### Auto-Commit Integration
* Automatically detect and commit any uncommitted work before PR operations
* Use `/project:do-commit` to ensure all changes are included
* Provide clear feedback about auto-committed changes
* Include auto-commit information in PR description

### Enhanced Auto-reviewer Assignment
* Use conventional commit scopes to assign relevant reviewers
* Parse CODEOWNERS file for scope-specific reviewers
* Match commit types to reviewer expertise (security team for auth changes, etc.)
* Respect review requirements from branch protection

### Integration Detection via Conventional Commits
* Detect `ci:` commits for CI/CD changes requiring platform team review
* Identify `build:` commits for dependency updates requiring security review
* Flag `feat:` commits with database scope for DBA review
* Recognize breaking changes from conventional commit analysis

### Template Integration
* Check for `.github/pull_request_template.md` in repository
* If template exists, use it as the base structure
* Auto-populate relevant sections with conventional commit analysis
* Preserve all custom template sections and formatting

## Success Criteria

### New PR Mode
* All uncommitted changes committed before PR creation
* Branch successfully pushed to remote
* PR created with conventional commit message as title (no translation)
* Description uses repository template if available, otherwise simple markdown list format
* Appropriate labels assigned based on conventional commit types
* Reviewers assigned based on commit scopes and types
* No conflicts with target branch

### Update PR Mode
* Any new uncommitted changes committed before update
* Latest changes pushed successfully
* PR description updated to reflect new conventional commit analysis
* Team notified of significant updates with commit type breakdown
* Labels updated based on new commit types
* CI/CD triggered for new changes

## Best Practices Enforced
* Always commit uncommitted changes before PR operations
* Never create PR from main branch
* Use conventional commit message directly as PR title (no translation)
* Leverage repository pull request template when available
* Use simple markdown lists for descriptions when no template exists
* Verify all changes are committed before creating PR
* Check for existing PR to avoid duplicates
* Use draft PRs for work-in-progress features
* Include structured context from conventional commit analysis
* Maintain consistency between commit analysis and PR descriptions
