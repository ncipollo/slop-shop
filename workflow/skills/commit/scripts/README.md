# Commit Skill Scripts

Scripts used by the `commit` skill to automate staging, committing, pushing, and fix-prefix detection.

---

## commit-and-push.sh

Stages all changes, commits with the provided message, and pushes to the remote. This is the main action script invoked by the skill after the commit message has been generated.

### Usage

```bash
./scripts/commit-and-push.sh "<commit message>"
```

Run from the user's git repository directory.

### Arguments

| Argument | Description |
|----------|-------------|
| `<commit message>` | The commit message to use (required) |

### Examples

```bash
./scripts/commit-and-push.sh "Fixes #42 Add user authentication"
./scripts/commit-and-push.sh "#42 Fix token expiry edge case"
./scripts/commit-and-push.sh "Update README"
```

### What It Does

1. Validates the current directory is a git repository
2. Checks that there are changes to commit
3. Stages all changes with `git add -A`
4. Commits with the provided message
5. Pushes the current branch to the remote (sets upstream automatically on first push)

### Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Changes staged, committed, and pushed |
| 1 | Not a git repo | Current directory is not a git repository |
| 2 | Nothing to commit | Working directory is clean |
| 3 | Commit failed | Check for pre-commit hook failures or other git errors |
| 4 | Push failed | Check remote configuration or authentication |

---

## should-fix.sh - Commit Fix Prefix Detection Script

Determines whether a commit message should include a `Fixes #<num>` prefix, based on the current branch name and commit count vs. the default branch.

## Overview

This script is used by the `commit` skill to decide the correct commit message format:
- **First commit** on a feature branch with an issue number → `Fixes #<num> <summary>` (auto-closes the GitHub issue on merge)
- **Subsequent commits** on the same branch → `#<num> <summary>` (references the issue without closing it)
- **No issue number** in branch → `<summary>` (plain message)

## Usage

```bash
./scripts/should-fix.sh [options]
```

Run from the user's git repository directory. The script takes no positional arguments.

### Options

- `--verbose`, `-v` — Enable detailed logging to stderr
- `--help`, `-h` — Display help message and exit

### Examples

```bash
# Basic usage
./scripts/should-fix.sh

# Verbose output for debugging
./scripts/should-fix.sh --verbose
```

## Output Format

On success (exit code 0), the script writes JSON to stdout:

```json
{
  "should_fix": true,
  "issue_number": 123,
  "branch": "username-issue-123-add-feature",
  "default_branch": "main",
  "commits_on_branch": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `should_fix` | boolean | True only if this is the first commit and an issue number was found |
| `issue_number` | integer \| null | Issue number parsed from the branch name, or null if none found |
| `branch` | string | Current branch name |
| `default_branch` | string | Detected default branch (main/master) |
| `commits_on_branch` | integer | Number of commits ahead of the default branch |

## Issue Number Parsing

The script uses two patterns to extract an issue number from the branch name:

1. **`issue-(\d+)` pattern** — Matches `issue-123` anywhere in the branch name
   - `username-issue-123-add-feature` → `123`
   - `fix-issue-456-crash` → `456`

2. **Bare number after first segment** — Strips the `<username>-` prefix, then checks for `^(\d+)-`
   - `username-42-fix-login` → `42`
   - `username-789-update-deps` → `789`

## Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | JSON output written to stdout |
| 1 | Not a git repo | Current directory is not a git repository |
| 2 | On default branch | Currently on main/master — not a feature branch |
| 3 | Can't detect default | Failed to detect the default branch |

## Default Branch Detection

The script uses the same detection strategy as `create-branch.sh`:

1. Check `origin/HEAD` symbolic ref (most reliable)
2. Fall back to looking for `main` or `master` local branches

## Troubleshooting

**Exit code 1 — Not a git repository:**
Run the script from within your git project directory.

**Exit code 2 — On default branch:**
The commit skill will proceed without a fix prefix. This is expected behavior when committing directly to main/master.

**Exit code 3 — Can't detect default branch:**
- Ensure `git remote` is configured
- Run `git remote set-head origin --auto` to set `origin/HEAD`
- Or ensure a `main` or `master` branch exists locally

**Issue number not found (`issue_number: null`):**
Branch name does not match either parsing pattern. Rename your branch to include `issue-<num>` or `<username>-<num>-<description>` if you want automatic issue linking.

## Integration with commit Skill

This script is called in Step 1 of the `commit` skill workflow. The skill reads the JSON output and uses `should_fix` and `issue_number` to format the commit message prefix.

Run `./scripts/should-fix.sh --help` for quick reference.
