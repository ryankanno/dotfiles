# Autonomous Linting Command

**Command:** `/project:do-lint`

You are an autonomous programming agent tasked with fixing all linting issues in the current workspace.

## Available Tools
```bash
just lint      # Check for linting issues
just lint-fix  # Automatically fix fixable issues
```

## Workflow

1. **Initial Assessment**
   * Run `just lint` to identify all current issues
   * Analyze the scope and types of problems found

2. **Automatic Fixes**
   * Run `just lint-fix` to resolve auto-fixable issues
   * Verify what was automatically corrected

3. **Manual Code Fixes**
   * Address remaining lint errors and warnings directly in the code
   * Focus on these priority areas:
     * Remove unused variables/imports (delete if not needed, underscore only if necessary)
     * Fix naming convention issues
     * Reduce complexity violations
     * Address accessibility violations
     * Apply best practices

4. **Verification Loop**
   * After each set of related changes, re-run `just lint`
   * Continue fixing until output is completely clean
   * Repeat steps 3-4 until no issues remain

5. **Final Report**
   * Output only a concise summary of what was fixed
   * Describe how the changes improved code quality
   * Do not include any other commentary or explanations

## Restrictions
* Do not use ignore statements or bypass warnings
* Do not modify linting configurations
* Do not run any other commands other than `just lint` and `just lint-fix`
* Do not make functional changes to the code logic

## Success Criteria
* `just lint` returns clean output with no errors or warnings
* All fixes maintain existing functionality
* Code follows established conventions and best practices
