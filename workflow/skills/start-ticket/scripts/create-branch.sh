#!/usr/bin/env bash

# create-branch.sh - Automated git branch creation script
# Part of the start-ticket skill for Claude Code
#
# Creates a feature branch following the <username>-<ticket>-<summary> convention
# with proper validation and error handling.

set -o pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_UNCOMMITTED_CHANGES=1
readonly EXIT_BRANCH_EXISTS=2
readonly EXIT_PULL_FAILED=3
readonly EXIT_INVALID_NAME=4
readonly EXIT_NOT_GIT_REPO=5
readonly EXIT_INVALID_ARGS=6

# Configuration
readonly MAX_BRANCH_LENGTH=50
readonly PRIMARY_BRANCHES=("main" "master")

# Global flags
VERBOSE=false

# Colors for output (if terminal supports it)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly RESET=$(tput sgr0)
else
    readonly RED=""
    readonly GREEN=""
    readonly YELLOW=""
    readonly BLUE=""
    readonly RESET=""
fi

# ============================================================================
# Output Functions
# ============================================================================

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "${BLUE}[VERBOSE]${RESET} $*" >&2
    fi
}

log_info() {
    echo "${GREEN}[INFO]${RESET} $*" >&2
}

log_error() {
    echo "${RED}[ERROR]${RESET} $*" >&2
}

log_warning() {
    echo "${YELLOW}[WARNING]${RESET} $*" >&2
}

# ============================================================================
# GitHub Username
# ============================================================================

get_github_username() {
    local cache_file="$HOME/.agent-cache/git-info.json"
    local cached_username=""

    # Try to read from cache
    if [[ -f "$cache_file" ]]; then
        log_verbose "Reading cached git info from $cache_file"
        cached_username=$(python3 -c "
import json, sys
try:
    with open('$cache_file') as f:
        data = json.load(f)
    print(data.get('github_username', ''))
except Exception:
    print('')
" 2>/dev/null)
    fi

    if [[ -n "$cached_username" ]]; then
        log_verbose "Using cached GitHub username: $cached_username"
        echo "$cached_username"
        return 0
    fi

    # Fall back to gh CLI
    log_verbose "Fetching GitHub username via gh CLI..."
    local username
    if ! username=$(gh api user --jq '.login' 2>/dev/null); then
        log_error "Failed to fetch GitHub username via gh CLI"
        log_error "Make sure gh is installed and authenticated: gh auth login"
        return 1
    fi

    if [[ -z "$username" ]]; then
        log_error "gh CLI returned empty username"
        return 1
    fi

    log_verbose "Fetched GitHub username: $username"

    # Cache the result
    mkdir -p "$(dirname "$cache_file")"
    python3 -c "
import json, os

cache_file = '$cache_file'
data = {}
if os.path.exists(cache_file):
    try:
        with open(cache_file) as f:
            data = json.load(f)
    except Exception:
        data = {}

data['github_username'] = '$username'

with open(cache_file, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

    echo "$username"
}

# ============================================================================
# Help and Usage
# ============================================================================

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <ticket-identifier> <summary> [options]

Create a feature branch following the <username>-<ticket>-<summary> convention.

Arguments:
  ticket-identifier    Ticket ID (e.g., issue-123) or descriptive slug
  summary             Brief 2-4 word summary (auto-formatted to kebab-case)

Options:
  --verbose, -v       Enable verbose output
  --help, -h          Show this help message

Examples:
  $(basename "$0") issue-123 "fix user login"
    → Creates: <username>-issue-123-fix-user-login

  $(basename "$0") issue-456 "add caching layer"
    → Creates: <username>-issue-456-add-caching-layer

  $(basename "$0") add-dark-mode "dark mode support"
    → Creates: <username>-add-dark-mode-dark-mode-support

Exit Codes:
  0    Success
  1    Uncommitted changes detected
  2    Branch already exists
  3    Pull failed (network/conflicts)
  4    Invalid branch name format
  5    Not a git repository
  6    Invalid arguments

For more information, see: scripts/README.md
EOF
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_git_repo() {
    log_verbose "Checking if current directory is a git repository..."

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not a git repository"
        log_error "Please run this script from within a git repository"
        return $EXIT_NOT_GIT_REPO
    fi

    log_verbose "Git repository confirmed"
    return 0
}

check_uncommitted_changes() {
    log_verbose "Checking for uncommitted changes..."

    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_error "Uncommitted changes detected in working directory"
        log_error "Please commit or stash your changes before creating a new branch"
        log_error ""
        log_error "Options:"
        log_error "  1. Commit changes:  git add . && git commit -m \"Your message\""
        log_error "  2. Stash changes:   git stash"
        log_error "  3. Discard changes: git reset --hard (WARNING: destructive)"
        return $EXIT_UNCOMMITTED_CHANGES
    fi

    log_verbose "Working directory is clean"
    return 0
}

format_branch_component() {
    local input="$1"
    local output

    # Convert to lowercase
    output=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    # Replace spaces and underscores with hyphens
    output=$(echo "$output" | tr '_ ' '-')

    # Remove special characters (keep alphanumeric and hyphens)
    output=$(echo "$output" | sed 's/[^a-z0-9-]//g')

    # Collapse multiple hyphens into single hyphen
    output=$(echo "$output" | sed 's/-\+/-/g')

    # Remove leading/trailing hyphens
    output=$(echo "$output" | sed 's/^-//; s/-$//')

    echo "$output"
}

generate_branch_name() {
    local ticket="$1"
    local summary="$2"
    local branch_prefix="$3"

    log_verbose "Generating branch name from ticket='$ticket' summary='$summary'"

    # Format each component
    local formatted_ticket=$(format_branch_component "$ticket")
    local formatted_summary=$(format_branch_component "$summary")

    # Build branch name
    local branch_name="${branch_prefix}-${formatted_ticket}-${formatted_summary}"

    # Truncate if too long (keep prefix and ticket intact, truncate summary if needed)
    if [[ ${#branch_name} -gt $MAX_BRANCH_LENGTH ]]; then
        log_verbose "Branch name too long (${#branch_name} chars), truncating to $MAX_BRANCH_LENGTH"

        local prefix_and_ticket="${branch_prefix}-${formatted_ticket}-"
        local remaining_length=$((MAX_BRANCH_LENGTH - ${#prefix_and_ticket}))

        if [[ $remaining_length -lt 5 ]]; then
            # Ticket ID itself is too long, truncate it too
            log_warning "Ticket ID is very long, truncating entire branch name"
            branch_name="${branch_name:0:$MAX_BRANCH_LENGTH}"
        else
            # Truncate summary part only
            formatted_summary="${formatted_summary:0:$remaining_length}"
            branch_name="${prefix_and_ticket}${formatted_summary}"
        fi

        # Remove trailing hyphen if truncation created one
        branch_name=$(echo "$branch_name" | sed 's/-$//')
    fi

    log_verbose "Generated branch name: $branch_name"
    echo "$branch_name"
}

validate_branch_name() {
    local branch_name="$1"
    local branch_prefix="$2"

    log_verbose "Validating branch name: $branch_name"

    # Check if empty
    if [[ -z "$branch_name" ]]; then
        log_error "Generated branch name is empty"
        return $EXIT_INVALID_NAME
    fi

    # Check if it follows the expected pattern
    if [[ ! "$branch_name" =~ ^${branch_prefix}- ]]; then
        log_error "Branch name does not start with required prefix: $branch_prefix"
        return $EXIT_INVALID_NAME
    fi

    # Check for invalid characters
    if [[ "$branch_name" =~ [^a-z0-9-] ]]; then
        log_error "Branch name contains invalid characters (only lowercase, numbers, and hyphens allowed)"
        return $EXIT_INVALID_NAME
    fi

    # Check length
    if [[ ${#branch_name} -gt $MAX_BRANCH_LENGTH ]]; then
        log_error "Branch name exceeds maximum length of $MAX_BRANCH_LENGTH characters"
        return $EXIT_INVALID_NAME
    fi

    log_verbose "Branch name is valid"
    return 0
}

check_branch_exists() {
    local branch_name="$1"

    log_verbose "Checking if branch already exists: $branch_name"

    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_error "Branch '$branch_name' already exists locally"
        log_error ""
        log_error "Options:"
        log_error "  1. Switch to existing branch:  git checkout $branch_name"
        log_error "  2. Delete and recreate:        git branch -D $branch_name"
        log_error "  3. Choose a different name"
        return $EXIT_BRANCH_EXISTS
    fi

    # Also check remote branches
    if git show-ref --verify --quiet "refs/remotes/origin/$branch_name"; then
        log_warning "Branch '$branch_name' exists on remote but not locally"
        log_warning "You may want to check out the remote branch instead"
    fi

    log_verbose "Branch does not exist, safe to create"
    return 0
}

# ============================================================================
# Git Operations
# ============================================================================

detect_primary_branch() {
    log_verbose "Detecting primary branch..."

    # Try to get the default branch from origin/HEAD
    local primary_branch
    primary_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    if [[ -n "$primary_branch" ]]; then
        log_verbose "Primary branch detected from origin/HEAD: $primary_branch"
        echo "$primary_branch"
        return 0
    fi

    # Fallback: check which of the common primary branches exists
    log_verbose "origin/HEAD not set, checking for common primary branches..."
    for branch in "${PRIMARY_BRANCHES[@]}"; do
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            log_verbose "Found primary branch: $branch"
            echo "$branch"
            return 0
        fi
    done

    # Last resort: use the first branch in the list of branches
    primary_branch=$(git branch --format='%(refname:short)' | head -n 1)
    if [[ -n "$primary_branch" ]]; then
        log_warning "Could not detect primary branch, using first available: $primary_branch"
        echo "$primary_branch"
        return 0
    fi

    log_error "Could not detect any primary branch"
    return 1
}

switch_to_primary_branch() {
    local primary_branch="$1"

    log_verbose "Switching to primary branch: $primary_branch"

    if ! git checkout "$primary_branch" 2>&1 | grep -v "Already on"; then
        log_error "Failed to switch to primary branch: $primary_branch"
        return 1
    fi

    log_verbose "Switched to $primary_branch"
    return 0
}

pull_latest_changes() {
    local primary_branch="$1"

    log_verbose "Pulling latest changes from origin/$primary_branch..."

    local pull_output
    if ! pull_output=$(git pull origin "$primary_branch" 2>&1); then
        log_error "Failed to pull latest changes from origin/$primary_branch"
        log_error ""
        log_error "Git output:"
        echo "$pull_output" | sed 's/^/  /' >&2
        log_error ""
        log_error "Possible causes:"
        log_error "  1. Network connectivity issues"
        log_error "  2. Merge conflicts with local changes"
        log_error "  3. Remote branch does not exist"
        log_error ""
        log_error "Try:"
        log_error "  1. Check network connection"
        log_error "  2. Run 'git pull' manually to see detailed error"
        log_error "  3. Ensure remote tracking is set up: git branch -u origin/$primary_branch"
        return $EXIT_PULL_FAILED
    fi

    log_verbose "Successfully pulled latest changes"
    if [[ "$pull_output" != *"Already up to date"* ]]; then
        log_info "Updated to latest changes from origin/$primary_branch"
    fi

    return 0
}

create_and_checkout_branch() {
    local branch_name="$1"

    log_verbose "Creating and checking out new branch: $branch_name"

    if ! git checkout -b "$branch_name" >/dev/null 2>&1; then
        log_error "Failed to create branch: $branch_name"
        return 1
    fi

    log_verbose "Successfully created and checked out branch: $branch_name"
    return 0
}

verify_branch_creation() {
    local branch_name="$1"

    log_verbose "Verifying branch creation..."

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [[ "$current_branch" != "$branch_name" ]]; then
        log_error "Branch verification failed: expected '$branch_name', got '$current_branch'"
        return 1
    fi

    log_verbose "Branch verification successful"
    return 0
}

# ============================================================================
# Main Workflow
# ============================================================================

main() {
    local ticket_identifier=""
    local summary=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "" >&2
                show_usage
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                if [[ -z "$ticket_identifier" ]]; then
                    ticket_identifier="$1"
                elif [[ -z "$summary" ]]; then
                    summary="$1"
                else
                    log_error "Too many arguments"
                    echo "" >&2
                    show_usage
                    exit $EXIT_INVALID_ARGS
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$ticket_identifier" ]] || [[ -z "$summary" ]]; then
        log_error "Missing required arguments"
        echo "" >&2
        show_usage
        exit $EXIT_INVALID_ARGS
    fi

    log_verbose "Starting branch creation workflow"
    log_verbose "Ticket: $ticket_identifier"
    log_verbose "Summary: $summary"

    # ========================================================================
    # PRE-FLIGHT VALIDATION (fail fast before any changes)
    # ========================================================================

    log_verbose "=== Pre-flight validation ==="

    # Check 1: Git repository
    validate_git_repo || exit $?

    # Check 2: Uncommitted changes
    check_uncommitted_changes || exit $?

    # Check 3: Fetch GitHub username for branch prefix
    local BRANCH_PREFIX
    if ! BRANCH_PREFIX=$(get_github_username); then
        log_error "Failed to determine GitHub username for branch prefix"
        exit 1
    fi
    log_verbose "Branch prefix: $BRANCH_PREFIX"

    # Check 4: Generate and validate branch name
    local branch_name
    branch_name=$(generate_branch_name "$ticket_identifier" "$summary" "$BRANCH_PREFIX")
    validate_branch_name "$branch_name" "$BRANCH_PREFIX" || exit $?

    # Check 5: Branch already exists
    check_branch_exists "$branch_name" || exit $?

    log_verbose "All pre-flight checks passed"

    # ========================================================================
    # EXECUTION (only after validation passes)
    # ========================================================================

    log_verbose "=== Executing git workflow ==="

    # Step 1: Detect primary branch
    local primary_branch
    if ! primary_branch=$(detect_primary_branch); then
        log_error "Failed to detect primary branch"
        exit 1
    fi

    # Step 2: Switch to primary branch
    if ! switch_to_primary_branch "$primary_branch"; then
        log_error "Failed to switch to primary branch"
        exit 1
    fi

    # Step 3: Pull latest changes
    if ! pull_latest_changes "$primary_branch"; then
        exit $EXIT_PULL_FAILED
    fi

    # Step 4: Create feature branch
    if ! create_and_checkout_branch "$branch_name"; then
        log_error "Failed to create feature branch"
        exit 1
    fi

    # Step 5: Verify success
    if ! verify_branch_creation "$branch_name"; then
        log_error "Branch creation verification failed"
        exit 1
    fi

    # ========================================================================
    # SUCCESS
    # ========================================================================

    log_info "Successfully created and switched to branch: $branch_name"

    # Output branch name to stdout (for programmatic use)
    echo "$branch_name"

    exit $EXIT_SUCCESS
}

# Run main function
main "$@"
