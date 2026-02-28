# create-branch.sh - Git Branch Creation Script

Automated script for creating feature branches following the `<username>-<ticket>-<summary>` convention with proper validation and error handling.

## Overview

This script consolidates the manual git workflow in the `start-ticket` skill into a single, reliable command. It handles:

- Primary branch detection (main/master)
- Uncommitted changes validation
- Branch name formatting and validation
- Duplicate branch detection
- Safe git operations with proper error handling

## Usage

```bash
./scripts/create-branch.sh <ticket-identifier> <summary> [options]
```

### Arguments

**Required:**
- `<ticket-identifier>` - Ticket ID (e.g., issue-123, issue-456) or descriptive slug
- `<summary>` - Brief 2-4 word summary describing the change

**Options:**
- `--verbose`, `-v` - Enable detailed logging of all operations
- `--help`, `-h` - Display help message and exit

### Examples

**Basic usage with GitHub issue:**
```bash
./scripts/create-branch.sh issue-123 "fix user login"
# Output: <username>-issue-123-fix-user-login
```

**With descriptive slug (no ticket):**
```bash
./scripts/create-branch.sh add-dark-mode "dark mode support"
# Output: <username>-add-dark-mode-dark-mode-support
```

**Verbose output for debugging:**
```bash
./scripts/create-branch.sh issue-456 "add caching" --verbose
# Shows detailed logs of each validation and git operation
```

## Branch Naming Convention

The script enforces this naming pattern:
```
<username>-<ticket>-<summary>
```

The `<username>` is your GitHub username, fetched automatically via `gh api user` and cached in `~/.agent-cache/git-info.json`.

### Automatic Formatting

The script automatically formats both ticket and summary inputs:

1. **Converts to lowercase**: `issue-123` → `issue-123`
2. **Replaces spaces/underscores with hyphens**: `Fix User Login` → `fix-user-login`
3. **Removes special characters**: `Fix: Login!` → `fix-login`
4. **Collapses multiple hyphens**: `fix---login` → `fix-login`
5. **Removes leading/trailing hyphens**: `-fix-login-` → `fix-login`
6. **Truncates to 50 characters** (keeping prefix and ticket intact)

## Exit Codes

The script uses specific exit codes for error handling:

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Branch created successfully |
| 1 | Uncommitted changes | Working directory has uncommitted changes |
| 2 | Branch exists | Branch with this name already exists |
| 3 | Pull failed | Failed to pull from remote (network/conflicts) |
| 4 | Invalid name | Generated branch name is invalid |
| 5 | Not a git repo | Current directory is not a git repository |
| 6 | Invalid arguments | Missing or incorrect arguments |

## Integration with start-ticket Skill

This script is designed to be called from the `start-ticket` skill's workflow.

**In SKILL.md (Step 2: Create Feature Branch):**

```bash
# Old (manual git commands):
git symbolic-ref refs/remotes/origin/HEAD
git checkout main
git pull origin main
git checkout -b <username>-issue-123-fix-login

# New (single script call):
./scripts/create-branch.sh issue-123 "fix-login"
```

The skill should:
1. Extract ticket identifier and summary from user input or GitHub
2. Call this script with those arguments
3. Handle exit codes appropriately:
   - Exit 0: Proceed with planning
   - Exit 1: Ask user about uncommitted changes
   - Exit 2: Ask user about existing branch
   - Exit 3: Inform about pull failure, offer retry
   - Others: Display error and ask for user input

## For More Information

See the full documentation in the script file itself, which includes:
- Detailed error handling strategies
- Troubleshooting guide for each error scenario
- Testing instructions
- Implementation details

Run `./scripts/create-branch.sh --help` for quick reference.
