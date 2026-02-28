---
name: start-ticket
description: |
  This skill should be used when the user asks to "start a ticket",
  "bootstrap a ticket", "begin work on a ticket", "set up ticket work",
  or provides a ticket identifier (like issue-123 or GitHub issue URL) and wants
  to start working on it. The skill handles the complete workflow from
  creating a feature branch to planning the implementation.
version: 1.0.0
---

# Ticket Bootstrap Skill

Automate the workflow for starting work on a new ticket, from branch creation to implementation planning.

## Overview

This skill handles the complete setup workflow when starting work on a ticket:
1. Identify the ticket and fetch details (GitHub/plain description)
2. Create a feature branch using the automated script (handles git workflow)
3. Enter plan mode
4. Create an implementation plan

## When to Use This Skill

Use this skill when:
- User provides a ticket identifier (e.g., "issue-123", "issue-456")
- User provides a Github issue URL
- User asks to "start work on [ticket]"
- User asks to "bootstrap [ticket]"
- User wants to begin implementation on a new task

## Workflow Steps

### Step 1: Identify the Ticket and Fetch Details

Extract the ticket identifier from the user's input and fetch the ticket details. This provides both the ticket ID and summary needed for branch creation.

**Input types:**
- GitHub issue URL (e.g., https://github.com/owner/repo/issues/32)
- Plain ticket name/description (e.g., "user authentication bug")

**For GitHub issues:**
1. Extract issue number from URL
2. Use `gh issue view <number>` to fetch issue details
3. Extract the issue title and description
4. Present issue information to the user for context

**For plain descriptions:**
1. Use the description as-is for branch naming
2. No additional fetching needed

The ticket summary/title will be used in Step 2 for generating the branch name.

### Step 2: Create Feature Branch

Use the `create-branch.sh` script to automate the git workflow. This script:
- Validates the working directory is clean (no uncommitted changes)
- Detects and switches to the primary branch (main/master)
- Pulls latest changes from origin
- Creates and checks out a new feature branch
- Validates the branch name format

**Script location:** `${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh`

**IMPORTANT:** The script MUST be executed from the user's current working directory (their git repository), NOT from the skill directory. Use the full path to the script while running it from the user's current working directory.

**Usage:**
```bash
${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh <ticket-identifier> <summary>
```

**Arguments:**
- `<ticket-identifier>`: The ticket key (e.g., issue-123) or a descriptive slug
- `<summary>`: A brief 2-4 word summary (will be auto-formatted to kebab-case)

**Examples:**
```bash
# GitHub issue-123 "Fix user login error"
${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh issue-123 "fix user login error"
# Creates: <username>-issue-123-fix-user-login-error

# Plain ticket "Add dark mode"
${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh add-dark-mode "dark mode support"
# Creates: <username>-add-dark-mode-dark-mode-support
```

**The script automatically formats branch names:**
- Converts to lowercase
- Replaces spaces/underscores with hyphens
- Removes special characters
- Truncates to 50 characters if needed

**IMPORTANT:** The script will exit with specific error codes if issues are detected. Handle these errors as described in the Error Handling section below.

### Step 3: Enter Plan Mode

Use the `EnterPlanMode` tool to transition into planning mode.

### Step 4: Create Implementation Plan

In plan mode, create a plan to implement the ticket or GitHub issue based on the details fetched in Step 1.

## Error Handling

The `create-branch.sh` script uses exit codes to indicate specific error conditions. Handle these gracefully by checking the exit code and providing appropriate guidance to the user.

**Exit Codes:**
- `0` - Success (branch created)
- `1` - Uncommitted changes detected
- `2` - Branch already exists
- `3` - Pull failed (network/conflicts)
- `4` - Invalid branch name format
- `5` - Not a git repository
- `6` - Invalid arguments

**Exit Code 1 - Uncommitted Changes:**
The script detected uncommitted changes. Present these options to the user:
```
There are uncommitted changes in the working directory.
Options:
1. Stash changes: git stash
2. Commit changes: git add . && git commit -m "Your message"
3. Discard changes: git reset --hard (WARNING: destructive)
```

**Exit Code 2 - Branch Already Exists:**
A branch with this name already exists. Present these options:
```
Branch '<branch-name>' already exists.
Options:
1. Switch to existing branch: git checkout <branch-name>
2. Delete and recreate: git branch -D <branch-name>
3. Choose a different summary for the branch name
```

**Exit Code 3 - Network/Pull Failures:**
Failed to pull latest changes from remote. Present these options:
```
Failed to pull latest changes from origin.
Possible causes:
- Network connectivity issues
- Merge conflicts
- Remote branch doesn't exist

Options:
1. Check network connection and retry
2. Run 'git pull' manually to see detailed error
3. Check remote tracking setup
```

**Exit Code 4 - Invalid Branch Name:**
The generated branch name is invalid (rare). Ask the user to:
```
Generated branch name is invalid.
Please provide simpler inputs without special characters.
```

**Exit Code 5 - Not a Git Repository:**
Script was run outside a git repository. Inform the user:
```
Current directory is not a git repository.
Please navigate to your repository first.
```

**Exit Code 6 - Invalid Arguments:**
Missing or incorrect arguments. This shouldn't happen if the skill provides the arguments correctly, but if it does:
```
Invalid arguments provided to create-branch.sh script.
Both ticket identifier and summary are required.
```

## Branch Naming Guidelines

The `create-branch.sh` script automatically enforces these conventions:
- Always prefix with `<username>-` (your GitHub username, fetched automatically)
- Use kebab-case (lowercase with hyphens)
- Keep total length under 50 characters
- Include ticket identifier if available
- Add 2-4 word summary
- Only alphanumeric characters and hyphens

**Automatic Formatting:**
The script automatically formats inputs, so you don't need to pre-format them:
- Converts to lowercase: `issue-123` → `issue-123`
- Replaces spaces/underscores with hyphens: `Fix User Login` → `fix-user-login`
- Removes special characters: `Fix: Login!` → `fix-login`
- Collapses multiple hyphens: `fix---login` → `fix-login`
- Truncates to 50 characters if needed

**Example transformations:**
- Input: `issue-123` + `Fix User Login` → `<username>-issue-123-fix-user-login`
- Input: `issue-456` + `Add: Caching Layer!` → `<username>-issue-456-add-caching-layer`
- Input: `add-dark-mode` + `Dark Mode Support` → `<username>-add-dark-mode-dark-mode-support`

**Best practices when calling the script:**
- Provide clear, descriptive summaries (the script will format them)
- Use 2-4 words for the summary
- Always include a ticket identifier when available
- Don't worry about case or special characters (script handles it)

## Example Usage

**Example 1: GitHub Issue**
```
User: "Start work on https://github.com/owner/repo/issues/32"

Agent workflow:
1. Extract issue number (32) and fetch: gh issue view 32 --repo owner/repo
   → Title: "Add support for MP3 files"
   → Present issue details to user
2. Create branch: ${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh issue-32 "add mp3 support"
   → Branch created: <username>-issue-32-add-mp3-support
3. Enter plan mode
4. Create implementation plan based on issue description
```

**Example 2: Plain Description**
```
User: "Start work on adding dark mode support"

Agent workflow:
1. Use plain description as-is
   → No fetching needed
2. Create branch: ${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh add-dark-mode "dark mode support"
   → Branch created: <username>-add-dark-mode-dark-mode-support
3. Enter plan mode
4. Create implementation plan
```

**Example 3: Error Handling - Uncommitted Changes**
```
User: "Start work on issue-789"

Agent workflow:
1. Fetch issue: gh issue view 789
   → Title: "Update authentication flow"
2. Try to create branch: ${CLAUDE_PLUGIN_ROOT}/skills/start-ticket/scripts/create-branch.sh issue-789 "update auth flow"
   → Script exits with code 1 (uncommitted changes)
3. Present options to user:
   "There are uncommitted changes. Would you like to:
    1. Stash changes and proceed
    2. Commit changes first
    3. Abort"
4. Handle user's choice and retry if appropriate
```
