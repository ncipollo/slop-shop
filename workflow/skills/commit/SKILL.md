---
name: commit
description: |
  Use this skill when the user wants to commit their work, saying "commit",
  "commit my work", "commit my changes", "make a commit", "save my progress",
  or similar. Stages changes, generates a smart commit message, and commits —
  automatically prefixing "Fixes #<num>" on the first commit of a feature
  branch to auto-close the GitHub issue on merge.
version: 1.0.0
---

# Commit Skill

Automate committing work with smart commit message formatting — detecting whether to include a `Fixes #<num>` prefix based on the current branch and commit history.

## Overview

This skill handles the full commit workflow:
1. Determine whether the commit message should include a fix prefix
2. Check the working directory state
3. Stage the appropriate files
4. Generate a clear commit message
5. Commit and verify

## When to Use This Skill

Use this skill when:
- User says "commit", "commit my work", or "commit my changes"
- User says "make a commit" or "save my progress"
- User says "commit and push" (commit first, then push separately)
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

### Step 2: Check Working Directory

Run `git status` to understand the state of the working directory.

**States to handle:**
- **Nothing to commit** — Inform user there is nothing to commit and stop
- **Staged changes only** — Proceed directly to commit message generation
- **Unstaged changes only** — Ask user which files to stage, or stage all with `git add -A`
- **Mixed staged + unstaged** — Show what's staged, ask if user wants to stage more

### Step 3: Stage Changes

Based on user input and the working directory state:

```bash
# Stage all changes
git add -A

# Stage specific files
git add <file1> <file2>

# Stage by pattern
git add src/
```

Confirm what is staged by running `git diff --cached --stat` and presenting the summary to the user.

### Step 4: Generate Commit Message

Analyze the staged diff to understand what changed:

```bash
git diff --cached
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

Present the generated message to the user before committing. Allow them to confirm or suggest changes.

### Step 5: Commit

Once the commit message is approved:

```bash
git commit -m "<message>"
```

Verify success by running `git status` and reporting the result to the user. Show the commit hash with `git log --oneline -1`.

---

## Error Handling

**Not a git repository (should-fix.sh exit code 1):**
```
Current directory is not a git repository.
Please navigate to your project directory first.
```

**Nothing to commit:**
```
Nothing to commit — working directory is clean.
```

**Commit fails:**
Check for common causes (pre-commit hooks, locked files, empty staged changes) and report the error output to the user.

---

## Example Usage

**Example 1: First Commit on Feature Branch**
```
User: "Commit my work"

Agent workflow:
1. Run should-fix.sh → { should_fix: true, issue_number: 42, commits_on_branch: 0 }
2. git status → modified files: src/auth.ts, src/login.ts
3. git add -A
4. git diff --cached → auth and login changes
5. Generate: "Fixes #42 Add user authentication"
6. Present to user, confirm
7. git commit -m "Fixes #42 Add user authentication"
8. Verify with git status + git log --oneline -1
```

**Example 2: Follow-up Commit on Same Branch**
```
User: "Commit my changes"

Agent workflow:
1. Run should-fix.sh → { should_fix: false, issue_number: 42, commits_on_branch: 1 }
2. git status → modified: src/auth.ts
3. git add -A
4. git diff --cached → token expiry fix
5. Generate: "#42 Fix token expiry edge case"
6. Present to user, confirm
7. git commit -m "#42 Fix token expiry edge case"
```

**Example 3: Commit on Main Branch**
```
User: "Commit my work"

Agent workflow:
1. Run should-fix.sh → exit code 2 (on default branch)
2. Proceed without fix prefix
3. git status → modified: README.md
4. git add -A
5. Generate: "Update README"
6. git commit -m "Update README"
```

**Example 4: No Issue Number in Branch**
```
User: "Commit"

Agent workflow:
1. Run should-fix.sh → { should_fix: false, issue_number: null, commits_on_branch: 0 }
2. Proceed without any prefix
3. git status, stage, generate: "Add dark mode toggle"
4. git commit -m "Add dark mode toggle"
```
