#!/usr/bin/env bash

# fetch-pr-comments.sh - Fetch PR review comments for the current branch
# Part of the address-pr-feedback skill for Claude Code
#
# Fetches both inline review comments and general discussion comments
# from the open PR associated with the current branch, outputting
# structured JSON to stdout for Claude to consume.

set -o pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_NOT_GIT_REPO=1
readonly EXIT_GH_NOT_INSTALLED=2
readonly EXIT_GH_NOT_AUTHENTICATED=3
readonly EXIT_NO_PR_FOUND=4
readonly EXIT_FETCH_FAILED=5

# Global flags
VERBOSE=false

# Colors for output (stderr only — stdout is JSON)
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
# Output Functions (all to stderr to keep stdout clean for JSON)
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

Fetch PR review comments for the current branch and output structured JSON.

Detects the open PR associated with the current git branch, then fetches
both inline code review comments and general discussion comments.

Options:
  --verbose, -v       Enable verbose output (to stderr)
  --help, -h          Show this help message

Output:
  JSON object on stdout:
  {
    "pr": { "number": 42, "title": "...", "url": "...", "branch": "..." },
    "review_comments": [...],   // inline code comments
    "issue_comments": [...]     // general discussion comments
  }

Exit Codes:
  0    Success — JSON output on stdout
  1    Not a git repository
  2    gh CLI not installed
  3    Not authenticated with gh
  4    No open PR found for current branch
  5    Failed to fetch comments

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

validate_gh_installed() {
    log_verbose "Checking if gh CLI is installed..."

    if ! command -v gh >/dev/null 2>&1; then
        log_error "gh CLI is not installed"
        log_error "Install it from: https://cli.github.com/"
        return $EXIT_GH_NOT_INSTALLED
    fi

    log_verbose "gh CLI found: $(command -v gh)"
    return 0
}

validate_gh_auth() {
    log_verbose "Checking gh authentication status..."

    if ! gh auth status >/dev/null 2>&1; then
        log_error "Not authenticated with gh CLI"
        log_error "Run: gh auth login"
        return $EXIT_GH_NOT_AUTHENTICATED
    fi

    log_verbose "gh authentication confirmed"
    return 0
}

# ============================================================================
# PR Detection
# ============================================================================

get_current_branch() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        log_error "Could not determine current branch (detached HEAD?)"
        return 1
    fi

    log_verbose "Current branch: $branch"
    echo "$branch"
}

get_pr_metadata() {
    local branch="$1"

    log_verbose "Looking for open PR for branch: $branch"

    local pr_json
    if ! pr_json=$(gh pr view --json number,title,headRefName,url 2>/dev/null); then
        log_error "No open PR found for branch: $branch"
        log_error ""
        log_error "Make sure:"
        log_error "  1. You are on the correct branch"
        log_error "  2. A PR has been opened for this branch"
        log_error "  3. The PR is not already merged or closed"
        return $EXIT_NO_PR_FOUND
    fi

    log_verbose "PR metadata retrieved"
    echo "$pr_json"
}

get_repo_info() {
    log_verbose "Fetching repository owner and name..."

    local repo_json
    if ! repo_json=$(gh repo view --json owner,name 2>/dev/null); then
        log_error "Failed to get repository info"
        return 1
    fi

    echo "$repo_json"
}

# ============================================================================
# Comment Fetching
# ============================================================================

fetch_review_comments() {
    local owner="$1"
    local repo="$2"
    local pr_number="$3"

    log_verbose "Fetching inline review comments for PR #$pr_number..."

    local comments
    if ! comments=$(gh api "repos/${owner}/${repo}/pulls/${pr_number}/comments" \
        --jq '[.[] | {
            id: .id,
            body: .body,
            author: .user.login,
            path: .path,
            line: (.line // .original_line),
            position: .position,
            created_at: .created_at,
            updated_at: .updated_at,
            in_reply_to_id: .in_reply_to_id,
            outdated: (.position == null)
        }]' 2>/dev/null); then
        log_warning "Failed to fetch inline review comments"
        echo "[]"
        return 0
    fi

    local count
    count=$(echo "$comments" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    log_verbose "Fetched $count inline review comments"
    echo "$comments"
}

fetch_issue_comments() {
    local owner="$1"
    local repo="$2"
    local pr_number="$3"

    log_verbose "Fetching general PR discussion comments for PR #$pr_number..."

    local comments
    if ! comments=$(gh api "repos/${owner}/${repo}/issues/${pr_number}/comments" \
        --jq '[.[] | {
            id: .id,
            body: .body,
            author: .user.login,
            path: null,
            line: null,
            created_at: .created_at,
            updated_at: .updated_at
        }]' 2>/dev/null); then
        log_warning "Failed to fetch general PR comments"
        echo "[]"
        return 0
    fi

    local count
    count=$(echo "$comments" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    log_verbose "Fetched $count general discussion comments"
    echo "$comments"
}

# ============================================================================
# JSON Assembly
# ============================================================================

build_json_output() {
    local pr_json="$1"
    local review_comments="$2"
    local issue_comments="$3"

    log_verbose "Assembling JSON output..."

    # Use python3 to safely merge everything
    python3 - "$pr_json" "$review_comments" "$issue_comments" <<'PYEOF'
import json, sys

pr_data = json.loads(sys.argv[1])
review_comments = json.loads(sys.argv[2])
issue_comments = json.loads(sys.argv[3])

output = {
    "pr": {
        "number": pr_data["number"],
        "title": pr_data["title"],
        "url": pr_data["url"],
        "branch": pr_data["headRefName"]
    },
    "review_comments": review_comments,
    "issue_comments": issue_comments
}

print(json.dumps(output, indent=2))
PYEOF
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

    log_verbose "Starting PR comment fetch workflow"

    # ========================================================================
    # PRE-FLIGHT VALIDATION
    # ========================================================================

    log_verbose "=== Pre-flight validation ==="

    validate_git_repo || exit $?
    validate_gh_installed || exit $?
    validate_gh_auth || exit $?

    log_verbose "All pre-flight checks passed"

    # ========================================================================
    # DETECT PR
    # ========================================================================

    log_verbose "=== Detecting PR ==="

    local current_branch
    if ! current_branch=$(get_current_branch); then
        log_error "Failed to detect current branch"
        exit 1
    fi

    local pr_json
    if ! pr_json=$(get_pr_metadata "$current_branch"); then
        exit $EXIT_NO_PR_FOUND
    fi

    local pr_number
    pr_number=$(echo "$pr_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['number'])")
    local pr_title
    pr_title=$(echo "$pr_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")

    log_info "Found PR #$pr_number: $pr_title"

    local repo_json
    if ! repo_json=$(get_repo_info); then
        log_error "Failed to fetch repository info"
        exit $EXIT_FETCH_FAILED
    fi

    local owner
    owner=$(echo "$repo_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['owner']['login'])")
    local repo_name
    repo_name=$(echo "$repo_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")

    log_verbose "Repository: $owner/$repo_name"

    # ========================================================================
    # FETCH COMMENTS
    # ========================================================================

    log_verbose "=== Fetching comments ==="

    local review_comments
    review_comments=$(fetch_review_comments "$owner" "$repo_name" "$pr_number")

    local issue_comments
    issue_comments=$(fetch_issue_comments "$owner" "$repo_name" "$pr_number")

    # ========================================================================
    # ASSEMBLE AND OUTPUT JSON
    # ========================================================================

    log_verbose "=== Assembling output ==="

    local output
    if ! output=$(build_json_output "$pr_json" "$review_comments" "$issue_comments"); then
        log_error "Failed to assemble JSON output"
        exit $EXIT_FETCH_FAILED
    fi

    log_info "Successfully fetched PR comments"

    # Output JSON to stdout
    echo "$output"

    exit $EXIT_SUCCESS
}

# Run main function
main "$@"
