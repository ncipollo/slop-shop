# fetch-assigned-issues.sh

Fetches open GitHub issues relevant to the authenticated `gh` user — either assigned to them or authored by them — across all repositories they can access, and outputs structured JSON to stdout.

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

On success (exit code 0), the script writes a JSON array to **stdout**, sorted by most recently updated first, capped at 50 results per query (assigned and authored — see "How It Works" below):

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
2. **Searches twice**: `gh search issues --assignee=@me --state=open` and `gh search issues --author=@me --state=open`, each spanning every repository the user can access — not just the current directory's repo. Two separate queries are needed because `gh search issues` has no OR syntax across qualifier types, and many personal workflows (e.g. self-filed backlog issues worked via `start-ticket`) never set the GitHub assignee field, so assignee-only search misses real work.
3. **Normalizes** each result shape with `gh`'s built-in `--jq` flag, flattening `repository.nameWithOwner` into `repo` and `labels[].name` into a plain string array
4. **Merges** both result sets, de-duplicates by `url`, and re-sorts by `updatedAt` descending

---

## Troubleshooting

**"Not authenticated with gh CLI"**
- Run: `gh auth login`
- Follow the prompts to authenticate with GitHub

**Script produces no output / empty array**
- Run with `--verbose` to see status messages on stderr
- Confirm you actually have open issues assigned to or authored by you: `gh search issues --assignee=@me --state=open` / `gh search issues --author=@me --state=open`
