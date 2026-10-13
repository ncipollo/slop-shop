# fetch-assigned-issues.sh

Fetches open GitHub issues assigned to the authenticated `gh` user, across all repositories they can access, and outputs structured JSON to stdout.

Part of the `list-issue` Claude Code skill.

---

## Usage

```bash
${CLAUDE_PLUGIN_ROOT}/skills/list-issue/scripts/fetch-assigned-issues.sh [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--verbose`, `-v` | Enable verbose status messages (to stderr) |
| `--help`, `-h` | Show usage information |

### Examples

```bash
# Basic usage
${CLAUDE_PLUGIN_ROOT}/skills/list-issue/scripts/fetch-assigned-issues.sh

# Verbose mode for debugging
${CLAUDE_PLUGIN_ROOT}/skills/list-issue/scripts/fetch-assigned-issues.sh --verbose
```

---

## Prerequisites

| Requirement | Check |
|-------------|-------|
| `gh` CLI installed | `command -v gh` |
| `gh` authenticated | `gh auth status` |
| `jq` | Used to normalize search results (bundled with `gh`'s `--jq` flag) |

---

## Output Format

On success (exit code 0), the script writes a JSON array to **stdout**, sorted by most recently updated first, capped at 50 results:

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

| Field | Type | Description |
|-------|------|-------------|
| `number` | integer | Issue number |
| `title` | string | Issue title |
| `url` | string | URL to the issue on GitHub |
| `repo` | string | `owner/repo` the issue belongs to |
| `updatedAt` | string | ISO 8601 timestamp of last update |
| `labels` | string[] | Label names on the issue |

All status/info messages are written to **stderr** so they don't pollute the JSON output.

---

## Exit Codes

| Code | Constant | Meaning |
|------|----------|---------|
| `0` | `EXIT_SUCCESS` | Success — JSON written to stdout |
| `1` | `EXIT_GH_NOT_INSTALLED` | `gh` CLI not installed |
| `2` | `EXIT_GH_NOT_AUTHENTICATED` | Not authenticated with `gh` |
| `3` | `EXIT_FETCH_FAILED` | Failed to fetch issues from GitHub |

---

## How It Works

1. **Validates** the environment (gh installed, gh authenticated)
2. **Searches** with `gh search issues --assignee=@me --state=open`, which spans every repository the user can access — not just the current directory's repo
3. **Normalizes** the result shape with `gh`'s built-in `--jq` flag, flattening `repository.nameWithOwner` into `repo` and `labels[].name` into a plain string array

---

## Troubleshooting

**"Not authenticated with gh CLI"**
- Run: `gh auth login`
- Follow the prompts to authenticate with GitHub

**Script produces no output / empty array**
- Run with `--verbose` to see status messages on stderr
- Confirm you actually have open issues assigned to you: `gh search issues --assignee=@me --state=open`
