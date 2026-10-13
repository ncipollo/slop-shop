---
name: list-issue
description: |
  Use this skill when the user wants to see the GitHub issues assigned to
  them, saying "list my issues", "show my assigned issues", "what issues
  do I have", "what's on my plate", "show open issues assigned to me",
  or similar. Fetches all open issues assigned to or authored by the
  authenticated gh user across every accessible repository, sorted by
  most recent activity, and renders them as an interactive artifact.
version: 1.0.0
---

# List Issue Skill

Show the user every open GitHub issue assigned to or authored by them, across all repositories they can access, as a clickable table artifact — with a one-click path into the `start-ticket` skill for whichever issue they want to pick up next.

## Overview

This skill handles the full issue-triage workflow:
1. Fetch all open issues assigned to or authored by the authenticated `gh` user, sorted by most recent activity (via the fetch script)
2. Build and publish a claude.ai Artifact rendering them as a table grouped by repo
3. Tell the user how to jump from a row straight into `start-ticket`

## When to Use This Skill

Use this skill when:
- User says "list my issues", "show my assigned issues", "what issues are assigned to me"
- User says "what's on my plate" or "what should I work on next"
- User wants a dashboard-style view of their open work across repos

## Important Limitation

A published Artifact is a sandboxed web page with no mechanism to call back into the Claude Code session that published it — there is no capability that lets a click in the page directly invoke a tool or skill here. So clicking a row **cannot** auto-run `start-ticket`. Instead, each row's button copies a ready-to-paste instruction to the clipboard; the user pastes it into the chat to actually kick off `start-ticket`. Do not imply or promise fully automatic hand-off — set this expectation if the user asks.

## Workflow Steps

### Step 1: Fetch Relevant Issues

Run the fetch script from the **user's current working directory**, using the full path:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/list-issue/scripts/fetch-assigned-issues.sh
```

For verbose output during debugging:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/list-issue/scripts/fetch-assigned-issues.sh --verbose
```

**IMPORTANT:** Execute from the user's working directory, NOT the skill directory. This search spans every repository the user can access — it is not limited to the current repo. It covers issues assigned to the user AND issues they authored, since many personal workflows (e.g. self-filed backlog issues worked via `start-ticket`) never set the GitHub assignee field — assignee-only search would silently miss those.

Handle exit codes before proceeding:
- **Exit code 0** — Success, parse the JSON array from stdout
- **Exit code 1** — `gh` not installed; inform user and stop
- **Exit code 2** — Not authenticated; inform user and stop
- **Exit code 3** — Fetch failed (network/API error); report and stop

On success, stdout is a JSON array sorted by most recently updated first:
```json
[
  {
    "number": 42,
    "title": "Add user authentication",
    "url": "https://github.com/owner/repo/issues/42",
    "repo": "owner/repo",
    "updatedAt": "2024-01-15T10:30:00Z",
    "labels": ["bug", "priority"]
  }
]
```

If the array is empty, tell the user they have no relevant open issues and stop — do not publish an empty artifact.

### Step 2: Build the Artifact

Use the `Artifact` tool. Before writing any HTML:
1. Call `Artifact` with `action: "quickstart"` and `intent: "other"` (this is a dashboard/table, not a document, deck, or design) — do this before loading any other skill or writing a file.
2. Load the `artifact-design` skill and follow its page contract (title, theming, layout, size limits).

**Content requirements:**
- Title: something like "My Open Issues".
- Group rows by repo (`repo`), with each group's issue count shown. Order the groups by their most-recently-updated issue first (i.e. just take the groups in the order their first member appears in the already-sorted input — don't re-sort groups alphabetically). Within a group, keep the given order (most-recently-updated first).
- Each row: issue number linked to `url`, title, labels (as small tags), and relative/human-readable `updatedAt`.
- Each row has a **Start** button. On click, it copies the following string to the clipboard and shows a brief "Copied!" confirmation on the button itself:
  ```
  start ticket <issue-url>
  ```
  Use the standard clipboard pattern so it degrades gracefully across browser contexts:
  ```js
  async function copyStartCommand(url, button) {
    const text = `start ticket ${url}`;
    try {
      await navigator.clipboard.writeText(text);
    } catch (e) {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }
    const original = button.textContent;
    button.textContent = 'Copied!';
    setTimeout(() => { button.textContent = original; }, 1500);
  }
  ```
- No runtime capabilities are needed — this is a static snapshot regenerated fresh each time the skill runs, not a page that needs to remember state or read live data. Omit `capabilities` (or pass `{}` on an update).
- Pass `icon: "list"` on first publish.

Publish with the `Artifact` tool, then `action: "open"` so the user sees it immediately.

### Step 3: Explain the Hand-off

After opening the artifact, tell the user:
- How many relevant open issues were found, and across how many repos
- That clicking **Start** on a row copies a `start ticket <url>` command to their clipboard
- That pasting it back into the chat will run the `start-ticket` skill for that issue

---

## Error Handling

**gh CLI not installed (exit code 1):**
```
The gh CLI is not installed. Install it from https://cli.github.com/ then run: gh auth login
```

**Not authenticated (exit code 2):**
```
Not authenticated with the gh CLI. Run: gh auth login
```

**Fetch failed (exit code 3):**
```
Failed to fetch your issues from GitHub. This may be a network issue or API error.
Try running manually with --verbose:
  ${CLAUDE_PLUGIN_ROOT}/skills/list-issue/scripts/fetch-assigned-issues.sh --verbose
```

**No relevant issues:**
```
You have no open issues currently assigned to or authored by you.
```

---

## Example Usage

**Example 1: Issues found across multiple repos**
```
User: "List my issues"

Agent workflow:
1. Run fetch-assigned-issues.sh → 12 open issues across 4 repos
2. Artifact quickstart (intent: other) → load artifact-design skill
3. Publish table artifact "My Open Issues" with a Start button per row
4. Open the artifact
5. Tell user: "You have 12 relevant open issues across 4 repos. Click Start
   on any row to copy a start-ticket command, then paste it here to begin."
```

**Example 2: No relevant issues**
```
User: "What's on my plate?"

Agent workflow:
1. Run fetch-assigned-issues.sh → []
2. Inform user: "You have no open issues currently assigned to or authored by you."
   (no artifact published)
```

**Example 3: Not authenticated**
```
User: "Show my assigned issues"

Agent workflow:
1. Run fetch-assigned-issues.sh → exit code 2
2. Inform user: "Not authenticated with the gh CLI. Run: gh auth login"
```

**Example 4: Hand-off into start-ticket**
```
User: "List my issues"
→ Artifact published, user clicks "Start" on issue #42 in repo owner/repo
→ Clipboard now contains: start ticket https://github.com/owner/repo/issues/42

User pastes: "start ticket https://github.com/owner/repo/issues/42"
→ Claude recognizes this as a request to start-ticket and follows that
  skill's workflow (fetch issue details, create branch, enter plan mode)
```
