---
name: commit
description: |
  Use this skill when the user wants to commit their work, saying "commit",
  "commit my work", "commit my changes", "make a commit", "save my progress",
  or similar. Stages changes, generates a smart commit message, commits, and
  pushes — automatically prefixing "Fixes #<num>" on the first commit of a
  feature branch to auto-close the GitHub issue on merge.
version: 1.1.0
---

# Commit Skill

Automate committing and pushing work with smart commit message formatting — detecting whether to include a `Fixes #<num>` prefix based on the current branch and commit history.

## Overview

This skill handles the full commit workflow:
1. Determine whether the commit message should include a fix prefix
2. Inspect the staged diff to understand what changed
3. Generate a clear commit message
4. Run `commit-and-push.sh` with the message — which stages all changes, commits, and pushes

## When to Use This Skill

Use this skill when:
- User says "commit", "commit my work", or "commit my changes"
- User says "make a commit" or "save my progress"
- User says "commit and push"
- User wants changes committed with a meaningful message

## Workflow Steps

### Step 1: Determine Fix Prefix

Run the `should-fix.sh` script from the **user's current working directory** (their git repo), using the full path:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/should-fix.sh
```

For verbose output during debugging:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/should-fix.sh --verbose
```

**IMPORTANT:** Execute from the user's working directory, NOT the skill directory.

Handle exit codes before proceeding:
- **Exit code 0** — Success, parse the JSON output
- **Exit code 1** — Not a git repo; inform user and stop
- **Exit code 2** — On default branch (no feature branch context); proceed without any fix prefix
- **Exit code 3** — Cannot detect default branch; proceed without any fix prefix, warn user

On success (exit code 0), the script outputs JSON to stdout:
```json
{
  "should_fix": true,
  "issue_number": 123,
  "branch": "username-issue-123-add-feature",
  "default_branch": "main",
  "commits_on_branch": 0
}
```

Parse `should_fix`, `issue_number`, and `commits_on_branch` from this output.

### Step 2: Generate Commit Message

Inspect the working tree diff to understand what changed:

```bash
git diff HEAD
```

Based on the diff, generate a concise commit message summary (imperative mood, present tense — e.g., "Add user authentication", not "Added user authentication").

**Apply the correct prefix based on `should-fix.sh` output:**

| Condition | Format |
|-----------|--------|
| `should_fix: true` (first commit, issue found) | `Fixes #<num> <summary>` |
| `should_fix: false`, `issue_number` present, commits > 0 | `#<num> <summary>` |
| No issue number found | `<summary>` |

**Examples:**
- First commit on `username-issue-42-add-auth`: `Fixes #42 Add user authentication`
- Second commit on same branch: `#42 Fix token expiry edge case`
- Commit on `main` or branchless: `Update dependencies`

### Step 3: Commit and Push

Run the `commit-and-push.sh` script from the **user's current working directory**, passing the generated commit message:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/commit-and-push.sh "<commit message>"
```

**IMPORTANT:** Execute from the user's working directory, NOT the skill directory.

The script will:
- Stage all changes (`git add -A`)
- Commit with the provided message
- Push to the remote (setting upstream automatically on first push)

Handle exit codes:
- **Exit code 0** — Success; report the result to the user
- **Exit code 1** — Not a git repo (should not happen if Step 1 passed)
- **Exit code 2** — Nothing to commit; inform the user and stop
- **Exit code 3** — Commit failed; report the error output to the user
- **Exit code 4** — Push failed; report the error output to the user

---

## Error Handling

**Not a git repository (should-fix.sh exit code 1):**
```
Current directory is not a git repository.
Please navigate to your project directory first.
```

**Nothing to commit (commit-and-push.sh exit code 2):**
```
Nothing to commit — working directory is clean.
```

**Commit fails (commit-and-push.sh exit code 3):**
Check for common causes (pre-commit hooks, locked files, empty staged changes) and report the error output to the user.

**Push fails (commit-and-push.sh exit code 4):**
Report the error output to the user. Common causes: no remote configured, authentication issues, or rejected push due to diverged history.

---

## Example Usage

**Example 1: First Commit on Feature Branch**
```
User: "Commit my work"

Agent workflow:
1. Run should-fix.sh → { should_fix: true, issue_number: 42, commits_on_branch: 0 }
2. git diff HEAD → auth and login changes
3. Generate: "Fixes #42 Add user authentication"
4. Run commit-and-push.sh "Fixes #42 Add user authentication"
   → git add -A, git commit, git push
```

**Example 2: Follow-up Commit on Same Branch**
```
User: "Commit my changes"

Agent workflow:
1. Run should-fix.sh → { should_fix: false, issue_number: 42, commits_on_branch: 1 }
2. git diff HEAD → token expiry fix
3. Generate: "#42 Fix token expiry edge case"
4. Run commit-and-push.sh "#42 Fix token expiry edge case"
```

**Example 3: Commit on Main Branch**
```
User: "Commit my work"

Agent workflow:
1. Run should-fix.sh → exit code 2 (on default branch)
2. Proceed without fix prefix
3. git diff HEAD → README changes
4. Generate: "Update README"
5. Run commit-and-push.sh "Update README"
```

**Example 4: No Issue Number in Branch**
```
User: "Commit"

Agent workflow:
1. Run should-fix.sh → { should_fix: false, issue_number: null, commits_on_branch: 0 }
2. Proceed without any prefix
3. git diff HEAD → dark mode toggle changes
4. Generate: "Add dark mode toggle"
5. Run commit-and-push.sh "Add dark mode toggle"
```
