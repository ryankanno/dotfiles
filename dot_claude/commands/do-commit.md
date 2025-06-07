# Autonomous Commit Command

**Command:** `/project:do-commit $ARGUMENTS`

You are an autonomous programming agent tasked with creating a commit for the current repository changes using conventional commit format.

## Available Tools
```bash
git status          # Check current repository state
git add .           # Stage all changes
git diff --staged   # Review staged changes
git commit -m       # Create commit with message
/project:do-conventional-commit-message  # Generate conventional commit message
```

## Workflow

1. **Check Repository State**
   * Run `git status` to understand current state
   * If no changes are staged but working directory has changes, run `git add .` to stage all changes
   * If no changes exist at all, report "No changes to commit" and exit

2. **Generate Commit Message**
   * Execute `/project:do-conventional-commit-message` to analyze changes and generate appropriate conventional commit message
   * The message generator will:
     * Analyze staged changes (or unstaged if nothing staged)
     * Determine the appropriate commit type (feat, fix, docs, etc.)
     * Generate a properly formatted conventional commit message
   * Capture the generated message from the tool's output

3. **Handle Arguments (if provided)**
   * If `$ARGUMENTS` are provided, use them to enhance or replace the description part of the generated message
   * Maintain the commit type and scope from the generator, but use provided arguments for description
   * Example: If generator suggests `feat(auth):` and arguments are "add OAuth2 support", combine to `feat(auth): add OAuth2 support`

4. **Create Commit**
   * Execute `git commit -m "<generated-message>"` using the message from the generator
   * Verify commit was created successfully

5. **Report Results**
   * Display the commit hash and full commit message
   * Show brief explanation of why this commit type was chosen (from generator output)
   * Confirm successful completion

## Integration with Conventional Commit Message Generator

The `/project:do-conventional-commit-message` tool will:
* Analyze repository state and changes
* Apply file-based and content-based heuristics
* Determine the most appropriate conventional commit type
* Generate a properly formatted message with optional scope
* Provide reasoning for the chosen type and description

## Usage Examples

* `/project:do-commit`
  * Generator analyzes changes and creates appropriate message
  * Example result: `feat(auth): add OAuth2 login integration`

* `/project:do-commit "improve error handling"`
  * Generator determines type/scope, uses provided description
  * Example result: `fix(api): improve error handling`

* `/project:do-commit`
  * With only README changes, generator produces: `docs: update installation instructions in README`

## Error Handling

* **No changes:** Report "No changes to commit" and exit
* **Commit fails:** Report the git error message and suggest resolution
* **Message generator fails:** Fall back to simple `chore: update repository` with warning
* **Ambiguous arguments:** Let the generator determine best fit, report reasoning

## Success Criteria

* Commit created successfully with conventional commit format
* Message follows exact conventional commit specifications
* Commit type accurately reflects the nature of changes
* All staged changes are included in the commit
* Clear reporting of what was committed and why

## Advantages of Using the Message Generator

1. **Intelligent Type Selection:** Analyzes actual file changes and content patterns
2. **Consistent Format:** Ensures all commits follow conventional commit standards
3. **Scope Detection:** Automatically identifies relevant scope based on changed files
4. **Better Descriptions:** Generated descriptions are based on actual changes, not just arguments
5. **Explanations:** Provides reasoning for commit type selection

## Notes

* The generator handles edge cases like breaking changes, multiple change types, and complex refactoring
* If arguments conflict with detected changes, prioritize accuracy (e.g., don't use "feat" for documentation-only changes)
* The generator's heuristics are continuously applied to ensure high-quality commit messages
