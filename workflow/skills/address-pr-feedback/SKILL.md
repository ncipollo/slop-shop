---
name: address-pr-feedback
description: |
  Use this skill when the user wants to address PR review comments/feedback,
  "fix PR feedback", "respond to PR comments", "address review comments",
  or similar. Fetches all comments from the PR on the current branch and
  creates a plan to address them.
version: 1.0.0
---

# Address PR Feedback Skill

Automate the workflow of triaging and addressing PR review comments — from fetching all feedback to creating a concrete implementation plan.

## Overview

This skill handles the full PR feedback workflow:
1. Fetch all comments from the PR associated with the current branch
2. Analyze and triage each comment
3. Enter plan mode
4. Create a structured, actionable implementation plan
5. Summarize what will be addressed vs. ignored

## When to Use This Skill

Use this skill when:
- User says "address PR feedback" or "address review comments"
- User says "fix PR comments" or "respond to PR comments"
- User says "address the review" or "work through PR feedback"
- User wants to systematically process and act on reviewer feedback before merging

## Workflow Steps

### Step 1: Fetch PR Comments

Run the fetch script from the **user's current working directory** (their git repo), using the full path:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh
```

For verbose output during debugging:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh --verbose
```

**IMPORTANT:** Execute from the user's working directory, NOT the skill directory.

Handle exit codes per the Error Handling section below before proceeding.

On success (exit code 0), the script outputs a JSON object to stdout:
```json
{
  "pr": { "number": 42, "title": "...", "url": "...", "branch": "..." },
  "review_comments": [...],
  "issue_comments": [...]
}
```

### Step 2: Analyze and Triage Comments

Parse the JSON output. For each comment:

1. **Read the comment body** and any context (file path and line number for inline comments)
2. **Categorize** the comment:
   - `code_change` — Reviewer wants specific code modified
   - `bug` — Reviewer identified a bug or incorrect behavior
   - `style` — Style/formatting suggestion
   - `nitpick` — Minor preference, low priority
   - `question` — Reviewer asking for clarification (may not require a code change)
   - `blocking` — Must be fixed before merge
   - `praise` — Positive feedback, no action needed
3. **Determine disposition**:
   - **Address** — Requires a code change or response
   - **Skip** — Already fixed, out of scope, bot comment, pure question answered inline, or `outdated: true`

Filter out:
- Comments where `outdated: true` (position is null — the code changed since the comment)
- Bot comments (author ending in `[bot]` or known bot names like `github-actions`, `dependabot`, `codecov`)
- Pure praise with no action item

### Step 3: Enter Plan Mode

Call the `EnterPlanMode` tool to transition into planning mode.

### Step 4: Create Implementation Plan

For each comment to address, create specific implementation steps:
- **File path** and line range
- **What to change** — concrete description of the fix
- **Why** — brief rationale tied back to the reviewer's concern

Group tasks by file for efficiency. Order blocking concerns before nitpicks.

### Step 5: Write Plan Summary

End the plan with two clearly labeled sections:

**Will Address:**
- Bullet list of comments being acted on
- For each: reviewer name, brief description of comment, and what change will be made

**Will Ignore / Skip:**
- Bullet list of comments being skipped
- For each: reviewer name, brief description, and reason for skipping
  - Reasons: `outdated`, `already fixed`, `bot comment`, `pure praise`, `question answered`, `out of scope`

---

## Error Handling

The `fetch-pr-comments.sh` script uses exit codes to indicate specific error conditions.

**Exit Code 1 — Not a Git Repository:**
```
Current directory is not a git repository.
Please navigate to your project directory first.
```

**Exit Code 2 — gh CLI Not Installed:**
```
The gh CLI is not installed.
Install it from: https://cli.github.com/
Then run: gh auth login
```

**Exit Code 3 — Not Authenticated:**
```
Not authenticated with the gh CLI.
Run: gh auth login
```

**Exit Code 4 — No Open PR Found:**
```
No open PR found for the current branch: <branch-name>

Make sure:
1. You are on the correct feature branch (not main/master)
2. A PR has been opened for this branch on GitHub
3. The PR is not already merged or closed
```

**Exit Code 5 — Failed to Fetch Comments:**
```
Failed to fetch PR comments.
This may be a network issue or a GitHub API error.
Try running the script manually with --verbose for details:
  ${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh --verbose
```

---

## Example Usage

**Example 1: Standard PR Review**
```
User: "Address the PR feedback"

Agent workflow:
1. Run: ${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh
   → PR #42: "Add user authentication"
   → 3 inline review comments, 2 discussion comments
2. Analyze:
   - reviewer: "You should use bcrypt instead of md5 here" → code_change (blocking)
   - reviewer: "Missing error handling in login flow" → bug (blocking)
   - reviewer: "nit: prefer const over let here" → nitpick
   - reviewer: "Looks good overall! 🎉" → praise → skip
   - bot: codecov[bot] coverage report → bot → skip
3. Enter plan mode
4. Create plan:
   - Fix auth/hash.ts:45 — replace md5 with bcrypt
   - Add error handling in auth/login.ts:87-92
   - Change let to const in auth/session.ts:12
5. Summary:
   Will Address: [3 items]
   Will Skip: [2 items — praise, bot comment]
```

**Example 2: No Open PR**
```
User: "Fix the PR comments"

Agent workflow:
1. Run script → exit code 4
2. Inform user: "No open PR found for branch 'main'.
   Are you on your feature branch? Try: git checkout <your-branch>"
```
