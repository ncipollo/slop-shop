#!/usr/bin/env bash

# commit-and-push.sh - Stage all changes, commit with a message, and push
# Part of the commit skill for Claude Code
#
# Usage: commit-and-push.sh "<commit message>"

set -o pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_NOT_GIT_REPO=1
readonly EXIT_NOTHING_TO_COMMIT=2
readonly EXIT_COMMIT_FAILED=3
readonly EXIT_PUSH_FAILED=4

# Colors for output (if terminal supports it)
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly RESET=$(tput sgr0)
else
    readonly RED=""
    readonly GREEN=""
    readonly YELLOW=""
    readonly RESET=""
fi

# ============================================================================
# Output Functions
# ============================================================================

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
Usage: $(basename "$0") "<commit message>"

Stage all changes (git add -A), commit with the provided message, and push
to the remote.

Arguments:
  <commit message>    The commit message to use (required, must be quoted)

Exit Codes:
  0    Success — changes staged, committed, and pushed
  1    Not a git repository
  2    Nothing to commit (working directory clean)
  3    Commit failed
  4    Push failed

Examples:
  $(basename "$0") "Fixes #42 Add user authentication"
  $(basename "$0") "#42 Fix token expiry edge case"
  $(basename "$0") "Update README"
EOF
}

# ============================================================================
# Main Workflow
# ============================================================================

main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit $EXIT_SUCCESS
    fi

    local commit_message="$1"

    if [[ -z "$commit_message" ]]; then
        log_error "Commit message cannot be empty"
        echo "" >&2
        show_usage
        exit 1
    fi

    # Step 1: Validate git repo
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not a git repository"
        log_error "Please run this script from within a git repository"
        exit $EXIT_NOT_GIT_REPO
    fi

    # Step 2: Check for changes
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        log_warning "Nothing to commit — working directory is clean"
        exit $EXIT_NOTHING_TO_COMMIT
    fi

    # Step 3: Stage all changes
    log_info "Staging all changes..."
    git add -A
    log_info "Staged files:"
    git diff --cached --stat >&2

    # Step 4: Commit
    log_info "Committing: $commit_message"
    if ! git commit -m "$commit_message"; then
        log_error "Commit failed"
        exit $EXIT_COMMIT_FAILED
    fi

    log_info "Committed successfully:"
    git log --oneline -1 >&2

    # Step 5: Push
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    log_info "Pushing branch '$current_branch' to remote..."
    if ! git push origin "$current_branch" 2>&1; then
        # Try setting upstream if push fails (first push on new branch)
        log_warning "Push failed, attempting to set upstream..."
        if ! git push --set-upstream origin "$current_branch"; then
            log_error "Push failed"
            exit $EXIT_PUSH_FAILED
        fi
    fi

    log_info "Pushed successfully"
    exit $EXIT_SUCCESS
}

main "$@"
