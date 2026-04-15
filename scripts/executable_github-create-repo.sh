#!/usr/bin/env bash
set -euo pipefail

# GitHub Repository Creation Script
# Automates repository creation with consistent settings

INTERACTIVE=false
REPO_NAME=""
ORG=""

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
    -o, --org ORG       Create repository under an organization
    -i, --interactive    Interactive mode (prompts for name and confirmation)
    -h, --help          Show this help message

EXAMPLES:
    $(basename "$0") my-new-project        Create repo immediately
    $(basename "$0") -o my-org my-project  Create repo under an organization
    $(basename "$0") -i                    Interactive mode

SETTINGS APPLIED:
    - Visibility: private
    - Merge: squash/merge/rebase (auto-merge enabled, delete on merge)
    - Features: issues, wiki, projects (discussions disabled)
    - Actions: enabled (all actions allowed)
    - Branch ruleset: main (signatures, linear history, PR reviews)

PREREQUISITES:
    - gh CLI installed and authenticated (gh auth login)
    - For org repos: caller must have repo-create permission in the org
    - Branch ruleset on private repos requires GitHub Pro (skipped with a
      warning otherwise; public repos and orgs typically support rulesets)

EXIT CODES:
    0  Success (ruleset may have been skipped — check stderr for warnings)
    1  Preflight or validation failure (missing gh, not authed, bad name)
    2  Repository creation failed (e.g. name already exists)
    3  Post-create configuration failed (settings, features, or ruleset)

NON-INTERACTIVE USE (for agents/automation):
    - Always pass REPO_NAME as a positional arg; do NOT use -i
    - Pass -o ORG to target an organization; omit for personal account
    - Script is idempotent-unsafe: re-running with the same name exits 2
    - Output is informational; parse exit code, not stdout, for success
    - All errors (including gh API responses) are printed to stderr

EXAMPLES FOR AGENTS:
    # Personal repo
    $(basename "$0") my-project || handle_failure \$?

    # Org repo
    $(basename "$0") -o my-org my-project
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
    local org="$2"
    local owner

    if [[ -n "$org" ]]; then
        owner="$org"
    else
        owner=$(gh api user --jq .login)
    fi

    echo "Creating repository '$repo_name' under '$owner'..."

    # Create private repository
    local create_args=("$repo_name" --private)
    if [[ -n "$org" ]]; then
        create_args=("$org/$repo_name" --private)
    fi
    if ! gh repo create "${create_args[@]}" 2>/dev/null; then
        print_error "Repository creation failed"
        exit 2
    fi
    print_success "Repository created"

    # Apply merge settings and features
    local patch_output
    if ! patch_output=$(gh api -X PATCH "repos/$owner/$repo_name" \
        -F allow_squash_merge=true \
        -F allow_merge_commit=true \
        -F allow_rebase_merge=true \
        -F allow_auto_merge=true \
        -F delete_branch_on_merge=true \
        -f squash_merge_commit_title=PR_TITLE \
        -f squash_merge_commit_message=COMMIT_MESSAGES \
        -f merge_commit_title=MERGE_MESSAGE \
        -f merge_commit_message=PR_TITLE \
        -F has_issues=true \
        -F has_projects=true \
        -F has_wiki=true \
        -F has_discussions=false 2>&1); then
        print_error "Failed to apply merge settings and features:"
        echo "$patch_output" >&2
        exit 3
    fi
    print_success "Merge settings applied"
    print_success "Features configured"

    # Set GitHub Actions permissions (non-fatal if already configured)
    local actions_output
    if actions_output=$(gh api -X PUT "repos/$owner/$repo_name/actions/permissions" \
        -F enabled=true \
        -f allowed_actions=all 2>&1); then
        print_success "Actions permissions set"
    else
        # Actions may already be configured correctly, verify
        if gh api "repos/$owner/$repo_name/actions/permissions" --jq '.enabled' 2>/dev/null | grep -q true; then
            print_success "Actions permissions verified"
        else
            print_warning "Could not verify Actions permissions:"
            echo "$actions_output" >&2
        fi
    fi

    # Create branch ruleset (requires GitHub Pro for private repos)
    local ruleset_output
    if ruleset_output=$(gh api -X POST "repos/$owner/$repo_name/rulesets" --input - 2>&1 <<'EOF'
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
    ); then
        print_success "Branch ruleset 'main' created"
    else
        if echo "$ruleset_output" | grep -qi "upgrade to github pro\|enable this feature"; then
            print_warning "Branch ruleset skipped (requires GitHub Pro for private repos)"
        else
            print_error "Failed to create branch ruleset:"
            echo "$ruleset_output" >&2
            exit 3
        fi
    fi

    echo ""
    echo "Done! https://github.com/$owner/$repo_name"
}

interactive_mode() {
    echo "GitHub Repository Creator (Interactive Mode)"
    echo ""

    # Prompt for organization (optional)
    read -r -p "Organization (leave empty for personal): " ORG

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
    create_repository "$REPO_NAME" "$ORG"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)
            ORG="$2"
            shift 2
            ;;
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
    create_repository "$REPO_NAME" "$ORG"
fi
