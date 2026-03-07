#!/usr/bin/env bash

# should-fix.sh - Determine whether a commit message should include "Fixes #<num>"
# Part of the commit skill for Claude Code
#
# Outputs JSON with fix prefix recommendation based on branch name and commit count.

set -o pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_NOT_GIT_REPO=1
readonly EXIT_ON_DEFAULT_BRANCH=2
readonly EXIT_CANT_DETECT_DEFAULT=3

# Configuration
readonly PRIMARY_BRANCHES=("main" "master")

# Global flags
VERBOSE=false

# Colors for output (if terminal supports it)
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
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
# Help and Usage
# ============================================================================

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Determine whether a commit message should include "Fixes #<num>" based on
the current branch name and commit history.

Options:
  --verbose, -v       Enable verbose output
  --help, -h          Show this help message

Output (stdout, JSON):
  {
    "should_fix": true,
    "issue_number": 123,
    "branch": "username-issue-123-add-feature",
    "default_branch": "main",
    "commits_on_branch": 0
  }

  should_fix is true only if:
  - On a feature branch (not the default branch)
  - An issue number was found in the branch name
  - No prior commits exist on the branch vs. the default branch

Exit Codes:
  0    Success
  1    Not a git repository
  2    On the default branch (not a feature branch)
  3    Cannot detect default branch

For more information, see: scripts/README.md
EOF
}

# ============================================================================
# Git Functions
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

detect_default_branch() {
    log_verbose "Detecting default branch..."

    # Try origin/HEAD first
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    if [[ -n "$default_branch" ]]; then
        log_verbose "Default branch detected from origin/HEAD: $default_branch"
        echo "$default_branch"
        return 0
    fi

    # Fallback: check common primary branches
    log_verbose "origin/HEAD not set, checking for common primary branches..."
    for branch in "${PRIMARY_BRANCHES[@]}"; do
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            log_verbose "Found default branch: $branch"
            echo "$branch"
            return 0
        fi
    done

    log_error "Could not detect default branch"
    return $EXIT_CANT_DETECT_DEFAULT
}

parse_issue_number() {
    local branch="$1"
    local issue_number=""

    log_verbose "Parsing issue number from branch: $branch"

    # Pattern 1: issue-(\d+) anywhere in the branch name
    if [[ "$branch" =~ issue-([0-9]+) ]]; then
        issue_number="${BASH_REMATCH[1]}"
        log_verbose "Found issue number via 'issue-N' pattern: $issue_number"
        echo "$issue_number"
        return 0
    fi

    # Pattern 2: bare number after first segment (strip <username>- prefix, then check ^(\d+)-)
    local stripped="$branch"
    # Remove leading <word>- prefix (the username segment)
    stripped=$(echo "$branch" | sed 's/^[^-]*-//')
    log_verbose "Stripped branch (after removing username prefix): $stripped"

    if [[ "$stripped" =~ ^([0-9]+)- ]]; then
        issue_number="${BASH_REMATCH[1]}"
        log_verbose "Found issue number via bare number pattern: $issue_number"
        echo "$issue_number"
        return 0
    fi

    log_verbose "No issue number found in branch name"
    echo ""
    return 0
}

# ============================================================================
# Main Workflow
# ============================================================================

main() {
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
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                echo "" >&2
                show_usage
                exit 1
                ;;
        esac
    done

    # Step 1: Validate git repo
    validate_git_repo || exit $?

    # Step 2: Detect default branch
    local default_branch
    if ! default_branch=$(detect_default_branch); then
        exit $EXIT_CANT_DETECT_DEFAULT
    fi

    # Step 3: Get current branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    log_verbose "Current branch: $current_branch"

    # Step 4: Exit with code 2 if on the default branch
    if [[ "$current_branch" == "$default_branch" ]]; then
        log_info "Currently on default branch '$default_branch' — not a feature branch"
        exit $EXIT_ON_DEFAULT_BRANCH
    fi

    # Step 5: Parse issue number from branch name
    local issue_number
    issue_number=$(parse_issue_number "$current_branch")

    # Step 6: Count commits on branch vs default
    local commits_on_branch
    commits_on_branch=$(git rev-list --count "${default_branch}..HEAD" 2>/dev/null)
    if [[ -z "$commits_on_branch" ]]; then
        commits_on_branch=0
    fi
    log_verbose "Commits on branch vs $default_branch: $commits_on_branch"

    # Step 7: Determine should_fix
    local should_fix="false"
    if [[ "$commits_on_branch" -eq 0 ]] && [[ -n "$issue_number" ]]; then
        should_fix="true"
    fi
    log_verbose "should_fix: $should_fix"

    # Step 8: Output JSON to stdout
    python3 - "$should_fix" "$issue_number" "$current_branch" "$default_branch" "$commits_on_branch" <<'PYEOF'
import json, sys

should_fix_str, issue_number_str, branch, default_branch, commits_str = sys.argv[1:]

data = {
    "should_fix": should_fix_str == "true",
    "issue_number": int(issue_number_str) if issue_number_str else None,
    "branch": branch,
    "default_branch": default_branch,
    "commits_on_branch": int(commits_str)
}

print(json.dumps(data, indent=2))
PYEOF

    exit $EXIT_SUCCESS
}

# Run main function
main "$@"
