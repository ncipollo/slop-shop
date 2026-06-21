---
name: pr
description: |
  Use this skill when the user wants to open a pull request, saying "open a PR",
  "create a PR", "make a pull request", "submit a PR", "push up a PR",
  or similar. Gathers branch context, drafts a concise PR title and description,
  then creates the PR via gh CLI.
version: 1.0.0
---

# PR Skill

Open a pull request with a well-formed title and description — derived from the branch's commits, with a human-readable summary and a hidden agent-context section for deep implementation detail.

## Overview

This skill handles the full PR creation workflow:
1. Gather branch context (commits, diff, existing PR)
2. Derive a title from the top commit, adjusting if there's topic drift across commits
3. Draft a description in the standard format
4. Push the branch if needed, then create the PR

## When to Use This Skill

Use this skill when:
- User says "open a PR", "create a PR", "make a pull request", "submit a PR"
- User says "push up a PR", "open a pull request", "send a PR"
- User says "PR this", "ship a PR", "put up a PR"
- User wants the current branch submitted for review

## PR Body Format

Every PR body produced by this skill MUST follow this exact structure — no deviations:

```
<1-2 sentence summary describing what this PR does and why. Plain prose, no headers, no bullets.>

- <Bullet 1: concise, high-level description of one aspect of the change>
- <Bullet 2>
- <Bullet 3>
- <Optional Bullet 4>

<details>
<summary>Agent Context</summary>

<Full context an agent would need to review or continue this work. Include: relevant file paths, affected components, key decisions made, related issues/PRs, architectural constraints, edge cases handled, and any "why not X" rationale. Be thorough — this section is for machines, not humans.>

</details>
```

**Rules for each section:**

- **Summary**: 1-2 sentences max. State what changed and why it matters. No jargon, no bullets. A non-technical reviewer should understand the intent at a glance.
- **Bullets**: 3-4 items. High-level *what* — not *how*. One complete thought per bullet. Avoid "we", "I", or action verbs like "I added"; keep them declarative ("New retry logic for flaky network calls").
- **Agent Context** (inside `<details>`): Dense and specific. Include file paths, function names, key decisions, related issues by number, constraints, known limitations, and any alternatives considered. This section is intentionally collapsed for human readers; write it for an AI agent or senior engineer doing deep review.

## Workflow Steps

### Step 1: Gather Branch Context

Run these commands from the user's current working directory:

```bash
# Identify base branch and list commits on this branch
git remote get-url origin 2>/dev/null || echo "(no remote)"
git rev-parse --abbrev-ref HEAD
git log --oneline $(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)..HEAD 2>/dev/null || git log --oneline -10

# Full diff for understanding the changes
git diff $(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)..HEAD 2>/dev/null || git diff HEAD~1..HEAD

# Check if a PR already exists for this branch
gh pr view --json number,title,body,url 2>/dev/null || echo "(no existing PR)"

# Check for project docs
ls CLAUDE.md README.md 2>/dev/null
```

Read `CLAUDE.md` and/or `README.md` if they exist — these provide architectural context for the Agent Context section.

Determine the base branch: prefer `main`, fall back to `master`, then whatever the default is reported by `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`.

### Step 2: Check for an Existing PR

If `gh pr view` succeeds (exit code 0), a PR already exists. In that case:
- Tell the user a PR is already open (show number and URL)
- Ask if they want to **update** the existing PR description instead of creating a new one
- If yes, follow the same draft → confirm → update flow using `gh pr edit`
- If no, stop

### Step 3: Derive the Title

**Single commit on branch:**
Use the first (and only) commit subject verbatim as the title — preserve any issue or ticket reference (e.g., `Fixes #42`, `#42`, `[PROJ-123]`).

**Multiple commits on branch:**
- Use the **first** (oldest) commit subject as the title — this is the commit that established the purpose of the branch and typically contains the issue or ticket reference
- Preserve the commit message as-is, including any issue/ticket prefix
- Read all commit subjects and the full diff to check for topic drift
- If later commits have significantly broadened the scope, append a brief qualifier to the first commit title rather than replacing it

**Title rules:**
- Preserve the first commit message verbatim when possible
- Keep issue/ticket references (e.g., `Fixes #42`, `#42`, `[PROJ-123]`) — they link the PR to the issue
- Under 72 characters; trim only if needed, keeping the issue reference intact
- Specific enough to be meaningful in a changelog

### Step 4: Draft the Description

Write a complete draft using the PR body format above.

**Summary paragraph guidance:**
- Describe what the PR does and the motivation, not the implementation steps
- If the first commit message or branch name contains an issue number, reference it naturally ("Closes #42") in the summary — the issue reference in the PR title (from the first commit) already links the PR to the issue

**Bullets guidance:**
- Derive from the diff and commit list
- Each bullet maps to a distinct logical change, not a file or commit
- Aim for 3 bullets; add a 4th only if there's a genuinely distinct fourth concern

**Agent Context guidance:**
- Restate the goal from an engineering perspective
- List key files changed (use the diff to enumerate them)
- Name affected components, modules, or services
- Call out decisions made (e.g., "Chose X over Y because Z")
- Link related issues/PRs by number
- Note edge cases handled or explicitly deferred
- Mention any follow-up work that was intentionally left out of scope

### Step 5: Push and Create

**Ensure the branch is pushed:**
```bash
git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD) 2>/dev/null || git push
```

**Create the PR:**
```bash
gh pr create \
  --title "<title>" \
  --body "<body>"
```

If a base branch other than `main`/`master` is needed, add `--base <branch>`.

**Updating an existing PR:**
```bash
gh pr edit <number> \
  --title "<title>" \
  --body "<body>"
```

Report the PR URL to the user when done.

---

## Error Handling

**Not a git repository:**
```
Current directory is not a git repository.
Please navigate to your project directory first.
```

**No commits ahead of base:**
```
No commits on this branch ahead of <base>. Nothing to PR.
```

**gh CLI not installed:**
```
The gh CLI is not installed. Install it from https://cli.github.com/ then run: gh auth login
```

**Not authenticated:**
```
Not authenticated with the gh CLI. Run: gh auth login
```

**Push fails:**
Report the error output to the user. Common causes: no remote configured, authentication issues, or protected branch rules.

**PR create fails:**
Report the error output verbatim. Suggest the user run `gh auth status` and verify remote access.

---

## Example Usage

**Example 1: Single-commit feature branch**
```
User: "Open a PR"

Agent workflow:
1. git log main..HEAD → 1 commit: "Fixes #42 Add dark mode toggle"
2. git diff main..HEAD → changes in src/theme/, src/components/Toggle.tsx
3. gh pr view → no existing PR
4. Title: "Fixes #42 Add dark mode toggle" (first commit message preserved as-is)
5. Draft body:
   - Summary: "Adds a dark mode toggle to the settings panel. Users can now switch themes without reloading."
   - Bullets: theme config, Toggle component, persistence via localStorage
   - Agent Context: file paths, theme system constraints, Closes #42
6. git push --set-upstream origin feature/42-dark-mode
7. gh pr create → https://github.com/owner/repo/pull/58
```

**Example 2: Multi-commit branch with drift**
```
User: "Create a PR"

Agent workflow:
1. git log main..HEAD (oldest → newest) →
   - "#12 Add retry logic to network client"   ← first commit
   - "#12 Fix test flakiness in NetworkClientTest"
   - "#12 Update changelog"
2. Use the first commit subject as title (preserving issue reference)
3. Title: "#12 Add retry logic to network client"
4. Draft body captures all three concerns in bullets
5. push + gh pr create
```

**Example 3: Existing PR found**
```
User: "Push up a PR"

Agent workflow:
1. gh pr view → PR #31 already exists: "Add dark mode"
2. Inform user: "PR #31 is already open (https://github.com/.../pull/31). Updating the description."
3. Draft new description from current diff
4. gh pr edit 31
```
