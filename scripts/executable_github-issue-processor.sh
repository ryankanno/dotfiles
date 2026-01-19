#!/bin/bash

# Parallel GitHub Issues Processor
# Fetches GitHub issues, creates worktrees, and runs Claude for each issue in parallel

set -uo pipefail

# Configuration
MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-5}  # Limit concurrent jobs
REPO=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
CLAUDE_PROMPT_FILE=${CLAUDE_PROMPT_FILE:-""}  # Optional: path to prompt file
ISSUE_FILTER=${ISSUE_FILTER:-"is:open is:issue"}  # Default filter for open issues

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local deps=("gh" "git" "claude")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        error "Please install the missing tools and try again."
        exit 1
    fi

    if ! command -v "git-worktree-toggle" &> /dev/null; then
        error "git-worktree-toggle command not found. Please ensure it's installed and in your PATH."
        exit 1
    fi
}

# Fetch GitHub issues
fetch_issues() {
    log "Fetching GitHub issues from $REPO with filter: $ISSUE_FILTER"

    local issues
    issues=$(gh issue list --repo "$REPO" --search "$ISSUE_FILTER" --json number,title --jq '.[] | "\(.number)|\(.title)"')

    if [[ -z "$issues" ]]; then
        warn "No issues found matching the filter criteria"
        exit 0
    fi

    echo "$issues"
}

# Process a single issue
process_issue() {
    local issue_line="$1"
    local issue_id="${issue_line%%|*}"
    local issue_title="${issue_line#*|}"
    local branch_name="fix/issue-${issue_id}"

    log "Processing issue #$issue_id: $issue_title"

    # Create worktree
    if ! git-worktree-toggle "$branch_name" 2>/dev/null; then
        error "Failed to create/toggle worktree for issue #$issue_id"
        return 1
    fi

    success "Created worktree for issue #$issue_id"

    # Prepare the full prompt
    local full_prompt=""

    # Add custom prompt file content if specified
    if [[ -n "$CLAUDE_PROMPT_FILE" && -f "$CLAUDE_PROMPT_FILE" ]]; then
        full_prompt="$(cat "$CLAUDE_PROMPT_FILE")"$'\n\n'
    fi

    # Add issue context to the prompt
    local issue_context="Please help complete GitHub issue #$issue_id: '$issue_title'. "
    issue_context+="Repository: $REPO. "
    issue_context+="Current branch: $branch_name. "

    # Get issue details
    local issue_body
    issue_body=$(gh issue view "$issue_id" --repo "$REPO" --json body --jq '.body // ""')

    if [[ -n "$issue_body" ]]; then
        issue_context+="Issue description: $issue_body"
    fi

    full_prompt+="$issue_context"

    # Run Claude with the combined prompt
    log "Running Claude for issue #$issue_id"
    log "Prompt: $full_prompt"

    if echo "$full_prompt" | claude --print --dangerously-skip-permissions > "claude-output-${issue_id}.log" 2>&1; then
        success "Claude completed processing for issue #$issue_id"
        log "Output saved to claude-output-${issue_id}.log"
    else
        error "Claude failed for issue #$issue_id (see claude-output-${issue_id}.log)"
        return 1
    fi
}

# Export functions for use in subshells
export -f log error success warn process_issue

# Main execution
main() {
    log "Starting parallel GitHub issues processor"

    # Check dependencies
    check_dependencies

    # Fetch issues
    local issues
    issues=$(fetch_issues)

    if [[ -z "$issues" ]]; then
        exit 0
    fi

    local issue_count
    issue_count=$(echo "$issues" | wc -l)

    log "Found $issue_count issues to process"
    log "Processing with max $MAX_PARALLEL_JOBS parallel jobs"

    # Export configuration variables for subshells
    export REPO CLAUDE_PROMPT_FILE RED GREEN YELLOW BLUE NC

    # Process issues in parallel using xargs
    echo "$issues" | xargs -I {} -P "$MAX_PARALLEL_JOBS" bash -c 'process_issue "$@"' _ {}

    success "All issues processed!"

    # Summary
    log "Summary of outputs:"
    for log_file in claude-output-*.log; do
        if [[ -f "$log_file" ]]; then
            echo "  - $log_file"
        fi
    done
}

# Help function
show_help() {
    cat << EOF
Parallel GitHub Issues Processor

Usage: $0 [OPTIONS]

This script fetches GitHub issues, creates git worktrees, and runs Claude
to help complete each issue in parallel.

Environment Variables:
  MAX_PARALLEL_JOBS    Maximum number of parallel jobs (default: 5)
  REPO                 GitHub repository (default: current repo)
  CLAUDE_PROMPT_FILE   Path to Claude prompt file (optional)
  ISSUE_FILTER         GitHub issue filter (default: "is:open is:issue")

Examples:
  # Process all open issues
  $0

  # Process with custom settings
  MAX_PARALLEL_JOBS=3 ISSUE_FILTER="is:open label:bug" $0

  # Use custom prompt file
  CLAUDE_PROMPT_FILE="./prompts/issue-solver.txt" $0

Requirements:
  - gh (GitHub CLI)
  - git
  - claude (Claude CLI)
  - git-worktree-toggle

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
