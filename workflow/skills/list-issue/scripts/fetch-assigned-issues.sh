#!/usr/bin/env bash

# fetch-assigned-issues.sh - Fetch open GitHub issues relevant to the current user
# Part of the list-issue skill for Claude Code
#
# Searches across all repositories the authenticated gh user can access for
# open issues either assigned to them or authored by them — many personal
# workflows (e.g. self-filed backlog issues worked via start-ticket) never
# set the GitHub assignee field, so assignee-only search misses real work —
# merges and de-duplicates the two result sets, and outputs structured JSON
# to stdout, sorted most-recently-updated first.

set -o pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GH_NOT_INSTALLED=1
readonly EXIT_GH_NOT_AUTHENTICATED=2
readonly EXIT_FETCH_FAILED=3

# Configuration
readonly RESULT_LIMIT=50

# Global flags
VERBOSE=false

# Colors for output (stderr only — stdout is JSON)
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly BLUE=$(tput setaf 4)
    readonly RESET=$(tput sgr0)
else
    readonly RED=""
    readonly GREEN=""
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

# ============================================================================
# Help and Usage
# ============================================================================

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Fetch open GitHub issues relevant to the authenticated gh user — either
assigned to them or authored by them — across all accessible repositories,
and output structured JSON sorted by most recent activity.

Options:
  --verbose, -v       Enable verbose output (to stderr)
  --help, -h          Show this help message

Output:
  JSON array on stdout, each item:
  {
    "number": 42,
    "title": "...",
    "url": "...",
    "repo": "owner/repo",
    "updatedAt": "2024-01-15T10:30:00Z",
    "labels": ["bug", "priority"]
  }

Exit Codes:
  0    Success — JSON output on stdout
  1    gh CLI not installed
  2    Not authenticated with gh
  3    Failed to fetch issues

For more information, see: scripts/README.md
EOF
}

# ============================================================================
# Validation Functions
# ============================================================================

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
# Issue Fetching
# ============================================================================

readonly NORMALIZE_FILTER='[.[] | {
    number: .number,
    title: .title,
    url: .url,
    repo: .repository.nameWithOwner,
    updatedAt: .updatedAt,
    labels: [.labels[].name]
}]'

# gh search issues has no OR syntax across qualifier types (assignee vs.
# author), so each is queried separately and the results are merged below.
fetch_issues_by_qualifier() {
    local qualifier="$1"
    local label="$2"

    log_verbose "Searching for open issues $label (limit $RESULT_LIMIT)..."

    local output
    if ! output=$(gh search issues \
        "$qualifier" \
        --state=open \
        --sort updated \
        --order desc \
        -L "$RESULT_LIMIT" \
        --json number,title,url,repository,updatedAt,labels \
        --jq "$NORMALIZE_FILTER" 2>/dev/null); then
        log_error "Failed to search GitHub issues ($label)"
        return 1
    fi

    echo "$output"
}

fetch_relevant_issues() {
    local assigned authored

    if ! assigned=$(fetch_issues_by_qualifier "--assignee=@me" "assigned to @me"); then
        log_error ""
        log_error "This may be a network issue or a GitHub API error."
        log_error "Try running manually with --verbose for details:"
        log_error "  $(basename "$0") --verbose"
        return $EXIT_FETCH_FAILED
    fi

    if ! authored=$(fetch_issues_by_qualifier "--author=@me" "authored by @me"); then
        log_error ""
        log_error "This may be a network issue or a GitHub API error."
        log_error "Try running manually with --verbose for details:"
        log_error "  $(basename "$0") --verbose"
        return $EXIT_FETCH_FAILED
    fi

    log_verbose "Merging and de-duplicating results, sorting by most recent activity..."

    jq -s 'add | unique_by(.url) | sort_by(.updatedAt) | reverse' \
        <(echo "$assigned") <(echo "$authored")
}

# ============================================================================
# Main Workflow
# ============================================================================

main() {
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
            *)
                log_error "Unknown option: $1"
                echo "" >&2
                show_usage
                exit 1
                ;;
        esac
    done

    log_verbose "Starting assigned-issues fetch workflow"

    validate_gh_installed || exit $?
    validate_gh_auth || exit $?

    local output
    output=$(fetch_relevant_issues) || exit $?

    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null || echo "?")
    log_info "Fetched $count relevant open issue(s)"

    echo "$output"

    exit $EXIT_SUCCESS
}

main "$@"
