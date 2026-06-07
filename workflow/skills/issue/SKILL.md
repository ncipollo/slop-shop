---
name: issue
description: |
  Use this skill when the user wants to create, reformat, or update a GitHub
  issue. Triggers: "create an issue", "draft an issue", "write a github issue",
  "refine issue #<num>", "reformat issue #<num>", "update issue #<num>",
  "fix up this issue", "address issue feedback", "make an issue for X",
  or similar. Gathers repo context, drafts or rewrites the issue in a
  structured format, confirms with the user, then creates or updates via gh CLI.
version: 1.0.0
---

# Issue Skill

Author, reformat, and update GitHub issues with a consistent structure: a human-readable summary, concise bullets, and a hidden agent-context section with full implementation detail.

## Overview

This skill handles three modes of issue work:
- **Create** — draft a new issue from the user's description and repo context
- **Reformat** — take a rough or unstructured existing issue and rewrite it into the standard format
- **Update** — incorporate feedback or new information into an existing issue's content

All three modes follow the same core loop: gather context → draft → confirm → publish.

## When to Use This Skill

Use this skill when:
- User says "create an issue", "draft an issue", "write a github issue about X", "make an issue for X"
- User says "refine issue #<num>", "reformat issue #<num>", "clean up issue #<num>", "fix up this issue"
- User says "update issue #<num>", "add context to issue #<num>", "address feedback on issue #<num>"
- User shares a rough issue description and wants it polished before publishing
- User wants to add engineering detail to a vague issue someone else wrote

## Issue Body Format

Every issue body produced by this skill MUST follow this exact structure — no deviations:

```
<2-3 sentence summary paragraph describing the problem being solved. Plain prose, no headers, no bullets.>

- <Bullet 1: concise, high-level description of one aspect of the change>
- <Bullet 2>
- <Bullet 3>
- <Optional Bullet 4>

<details>
<summary>Agent Context</summary>

<Full context an agent would need to solve this effectively. Include: relevant file paths, affected components, constraints, related issues, technical background, edge cases, and any prior art. Be thorough — this section is for machines, not humans.>

</details>
```

**Rules for each section:**

- **Summary paragraph**: 2-3 sentences max. State the problem, not the solution. No jargon, no bullets, no headers. A non-technical reader should understand why this matters.
- **Bullets**: 3-4 items. High-level only — the *what*, not the *how*. Unopinionated (avoid "we should", "we must"). Each bullet is one complete thought.
- **Agent Context** (inside `<details>`): Dense and specific. Include file paths, function names, config keys, related PRs/issues, architectural constraints, known edge cases. This section is intentionally hidden from casual readers; write it for an AI agent or a senior engineer who needs full context fast.

## Workflow Steps

### Step 1: Determine Mode

Identify which of the three modes applies:

| Signal | Mode |
|--------|------|
| No issue number mentioned, user describes a problem/feature | **Create** |
| Issue number given, user wants it cleaned up / reformatted | **Reformat** |
| Issue number given, user wants to add/change specific content | **Update** |

When in doubt, ask one targeted question. Don't ask multiple questions at once.

### Step 2: Gather Repo Context

Run these commands from the user's current working directory to build context for a grounded issue:

```bash
# Repo identity and recent history
git remote get-url origin 2>/dev/null || echo "(no remote)"
git log --oneline -20

# Check for project docs
ls CLAUDE.md README.md 2>/dev/null

# Open issues (to avoid duplicates, find related issues)
gh issue list --limit 20 --state open 2>/dev/null
```

Read `CLAUDE.md` and/or `README.md` if they exist — these contain architectural context that should inform the Agent Context section.

### Step 3: Fetch the Existing Issue (Reformat / Update modes)

```bash
gh issue view <number> --json number,title,body,labels,assignees,comments
```

Extract the title, body, and any discussion comments. Comments often contain feedback or clarifying context that belongs in the Agent Context section — read them all.

For **Reformat**: treat the existing body as raw material. Preserve the intent and any specific details while restructuring into the standard format.

For **Update**: identify what new information the user wants incorporated (feedback, decisions, new constraints) and merge it into the existing structure.

### Step 4: Draft the Issue

Write a complete draft — title and body — using the format above.

**Title guidelines:**
- Imperative mood: "Add X", "Fix Y", "Support Z"
- Under 72 characters
- No issue number prefix

**Agent Context guidelines:**
- Start with a brief restatement of the goal from an engineering perspective
- List relevant file paths (use `find` or `grep` to locate them if unsure)
- Name affected components, modules, or services
- Call out constraints: API contracts, backwards compatibility, performance budgets, etc.
- Link related issues/PRs by number (e.g., "Related: #42")
- Note known edge cases or failure modes
- Surface any context from issue comments that adds implementation detail
- If there's existing code to change, describe the current behavior concisely

### Step 5: Confirm with the User

Present the full draft (title + body) before touching GitHub:

> Here's the draft. Let me know if you'd like any changes before I publish it.

If the user requests changes, revise and re-show. Repeat until the user approves.

Do NOT create or update the issue until the user explicitly approves (a "yes", "looks good", "go ahead", "publish it", or equivalent).

### Step 6: Publish

**Creating a new issue:**
```bash
gh issue create \
  --title "<title>" \
  --body "<body>"
```

**Updating an existing issue:**
```bash
gh issue edit <number> \
  --title "<title>" \
  --body "<body>"
```

Report the issue URL to the user when done.

---

## Error Handling

**gh CLI not installed:**
```
The gh CLI is not installed. Install it from https://cli.github.com/ then run: gh auth login
```

**Not authenticated:**
```
Not authenticated with the gh CLI. Run: gh auth login
```

**Not a GitHub repo:**
```
This directory doesn't appear to be linked to a GitHub repository.
Check your remote: git remote -v
```

**Issue not found:**
```
Issue #<num> not found. Check the issue number and try again.
```

**gh command fails:**
Report the error output verbatim and suggest the user run `gh auth status`.

---

## Example Usage

**Example 1: Create a new issue**
```
User: "Create a GitHub issue for adding dark mode support"

Agent workflow:
1. git log, gh issue list → no existing dark mode issue
2. Check CLAUDE.md → finds theming system in src/theme/
3. Draft title + body in standard format
4. Show draft to user → user approves
5. gh issue create → https://github.com/owner/repo/issues/57
```

**Example 2: Reformat a rough existing issue**
```
User: "Refine issue #23"

Agent workflow:
1. gh issue view 23 → title "dark mode", body is a rough one-liner
2. Read CLAUDE.md → theming system details
3. Expand the one-liner into full structured format:
   - Write summary paragraph from the rough description
   - Extract 3-4 bullets from the intent
   - Populate Agent Context with file paths and constraints from repo
4. Show draft → user says "add a note about RTL support"
5. Revise Agent Context to mention RTL
6. User approves → gh issue edit 23
```

**Example 3: Update issue with feedback**
```
User: "Update issue #31 — we decided to use the existing cache layer instead of adding Redis"

Agent workflow:
1. gh issue view 31 → reads full body and comments
2. Identifies where Redis is mentioned in Agent Context
3. Replaces Redis references with the existing cache layer approach
4. Notes the decision with brief rationale in Agent Context
5. Show revised draft → user approves
6. gh issue edit 31
```

**Example 4: Vague create request**
```
User: "Make an issue"

Agent workflow:
1. Ask: "What problem or feature should this issue cover?"
2. User: "the login is broken on Safari"
3. Gather context → find auth code in src/auth/
4. Draft issue with specific Safari/auth context
5. Confirm and create
```
