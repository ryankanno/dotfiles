#!/usr/bin/env bash
set -euo pipefail

# GitHub Repository Creation Script
# Automates repository creation with consistent settings

INTERACTIVE=false
REPO_NAME=""

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [REPO_NAME]

Create a GitHub repository with consistent settings.

OPTIONS:
    -i, --interactive    Interactive mode (prompts for name and confirmation)
    -h, --help          Show this help message

EXAMPLES:
    $(basename "$0") my-new-project        Create repo immediately
    $(basename "$0") -i                    Interactive mode

SETTINGS APPLIED:
    - Visibility: private
    - Merge: squash/merge/rebase (auto-merge enabled, delete on merge)
    - Features: issues, wiki, projects (discussions disabled)
    - Actions: enabled (all actions allowed)
    - Branch ruleset: main (signatures, linear history, PR reviews)
EOF
    exit 0
}

validate_repo_name() {
    local name="$1"

    # Check length
    if [[ ${#name} -gt 100 ]]; then
        print_error "Repository name too long (max 100 characters)"
        return 1
    fi

    # Check if starts with period
    if [[ "$name" =~ ^\. ]]; then
        print_error "Repository name cannot start with a period"
        return 1
    fi

    # Check valid characters (alphanumeric, hyphen, underscore, period)
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        print_error "Repository name can only contain alphanumeric characters, hyphens, underscores, and periods"
        return 1
    fi

    return 0
}

preflight_checks() {
    # Check gh CLI is installed
    if ! command -v gh >/dev/null 2>&1; then
        print_error "gh CLI not found. Install from: https://cli.github.com/"
        exit 1
    fi

    # Check gh authentication
    if ! gh auth status >/dev/null 2>&1; then
        print_error "Not authenticated with GitHub. Run: gh auth login"
        exit 1
    fi
}

show_settings_summary() {
    cat <<EOF

Settings to apply:
  - Visibility: private
  - Merge: squash/merge/rebase (auto-merge enabled, delete on merge)
  - Features: issues, wiki, projects (discussions disabled)
  - Actions: enabled (all actions allowed)
  - Branch ruleset: main (signatures, linear history, PR reviews)

EOF
}

create_repository() {
    local repo_name="$1"
    local owner

    # Get authenticated user
    owner=$(gh api user --jq .login)

    echo "Creating repository '$repo_name'..."

    # Create private repository
    if ! gh repo create "$repo_name" --private 2>/dev/null; then
        print_error "Repository creation failed"
        exit 2
    fi
    print_success "Repository created"

    # Apply merge settings and features
    if ! gh api -X PATCH "repos/$owner/$repo_name" \
        -f allow_squash_merge=true \
        -f allow_merge_commit=true \
        -f allow_rebase_merge=true \
        -f allow_auto_merge=true \
        -f delete_branch_on_merge=true \
        -f squash_merge_commit_title=PR_TITLE \
        -f squash_merge_commit_message=COMMIT_MESSAGES \
        -f merge_commit_title=MERGE_MESSAGE \
        -f merge_commit_message=PR_TITLE \
        -f has_issues=true \
        -f has_projects=true \
        -f has_wiki=true \
        -F has_discussions=false >/dev/null 2>&1; then
        print_error "Failed to apply merge settings and features"
        exit 3
    fi
    print_success "Merge settings applied"
    print_success "Features configured"

    # Set GitHub Actions permissions (non-fatal if already configured)
    if gh api -X PUT "repos/$owner/$repo_name/actions/permissions" \
        -f enabled=true \
        -f allowed_actions=all >/dev/null 2>&1; then
        print_success "Actions permissions set"
    else
        # Actions may already be configured correctly, verify
        if gh api "repos/$owner/$repo_name/actions/permissions" --jq '.enabled' 2>/dev/null | grep -q true; then
            print_success "Actions permissions verified"
        else
            print_warning "Could not verify Actions permissions"
        fi
    fi

    # Create branch ruleset
    if ! gh api -X POST "repos/$owner/$repo_name/rulesets" --input - >/dev/null 2>&1 <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {"type": "required_signatures"},
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": true,
        "require_last_push_approval": true,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash", "rebase"]
      }
    }
  ],
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ]
}
EOF
    then
        print_error "Failed to create branch ruleset"
        exit 3
    fi
    print_success "Branch ruleset 'main' created"

    echo ""
    echo "Done! https://github.com/$owner/$repo_name"
}

interactive_mode() {
    echo "GitHub Repository Creator (Interactive Mode)"
    echo ""

    # Prompt for repository name
    read -r -p "Repository name: " REPO_NAME

    # Validate
    if [[ -z "$REPO_NAME" ]]; then
        print_error "Repository name cannot be empty"
        exit 1
    fi

    if ! validate_repo_name "$REPO_NAME"; then
        exit 1
    fi

    # Show settings
    show_settings_summary

    # Confirm
    read -r -p "Create repository? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    echo ""
    create_repository "$REPO_NAME"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            print_error "Unknown option: $1"
            usage
            ;;
        *)
            REPO_NAME="$1"
            shift
            ;;
    esac
done

# Run preflight checks
preflight_checks

# Execute
if [[ "$INTERACTIVE" == true ]]; then
    interactive_mode
else
    # Direct mode requires repo name
    if [[ -z "$REPO_NAME" ]]; then
        print_error "Repository name required in direct mode"
        echo ""
        usage
    fi

    # Validate
    if ! validate_repo_name "$REPO_NAME"; then
        exit 1
    fi

    # Create
    create_repository "$REPO_NAME"
fi
