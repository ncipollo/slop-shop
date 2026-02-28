# fetch-pr-comments.sh

Fetches PR review comments for the current branch and outputs structured JSON to stdout.

Part of the `address-pr-feedback` Claude Code skill.

---

## Usage

```bash
${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh [options]
```

**IMPORTANT:** Run from the user's git repository directory, not from the skill directory.

### Options

| Option | Description |
|--------|-------------|
| `--verbose`, `-v` | Enable verbose status messages (to stderr) |
| `--help`, `-h` | Show usage information |

### Examples

```bash
# Basic usage — run from a git repo with an open PR
${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh

# Verbose mode for debugging
${CLAUDE_PLUGIN_ROOT}/skills/address-pr-feedback/scripts/fetch-pr-comments.sh --verbose
```

---

## Prerequisites

| Requirement | Check |
|-------------|-------|
| `git` repository | Must be run from inside a git repo |
| `gh` CLI installed | `command -v gh` |
| `gh` authenticated | `gh auth status` |
| Open PR on current branch | PR must be open (not merged/closed) |
| `python3` | Used for JSON assembly |

---

## Output Format

On success (exit code 0), the script writes a JSON object to **stdout**:

```json
{
  "pr": {
    "number": 42,
    "title": "Add user authentication",
    "url": "https://github.com/owner/repo/pull/42",
    "branch": "<username>-issue-42-add-auth"
  },
  "review_comments": [
    {
      "id": 123456,
      "body": "You should use bcrypt instead of md5 here.",
      "author": "some-reviewer",
      "path": "src/auth/hash.ts",
      "line": 45,
      "position": 3,
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T10:30:00Z",
      "in_reply_to_id": null,
      "outdated": false
    }
  ],
  "issue_comments": [
    {
      "id": 789012,
      "body": "Overall this looks good, just a few small things.",
      "author": "some-reviewer",
      "path": null,
      "line": null,
      "created_at": "2024-01-15T11:00:00Z",
      "updated_at": "2024-01-15T11:00:00Z"
    }
  ]
}
```

### Fields

**`pr` object:**
| Field | Type | Description |
|-------|------|-------------|
| `number` | integer | PR number |
| `title` | string | PR title |
| `url` | string | URL to the PR on GitHub |
| `branch` | string | Head branch name |

**`review_comments` items (inline code comments):**
| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Comment ID |
| `body` | string | Comment text |
| `author` | string | GitHub username of commenter |
| `path` | string | File path the comment is on |
| `line` | integer\|null | Line number in the file |
| `position` | integer\|null | Position in the diff (null if outdated) |
| `created_at` | string | ISO 8601 timestamp |
| `updated_at` | string | ISO 8601 timestamp |
| `in_reply_to_id` | integer\|null | ID of parent comment if this is a reply |
| `outdated` | boolean | `true` if the code has changed since this comment (position is null) |

**`issue_comments` items (general discussion):**
| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Comment ID |
| `body` | string | Comment text |
| `author` | string | GitHub username of commenter |
| `path` | null | Always null (not associated with a file) |
| `line` | null | Always null |
| `created_at` | string | ISO 8601 timestamp |
| `updated_at` | string | ISO 8601 timestamp |

All status/info messages are written to **stderr** so they don't pollute the JSON output.

---

## Exit Codes

| Code | Constant | Meaning |
|------|----------|---------|
| `0` | `EXIT_SUCCESS` | Success — JSON written to stdout |
| `1` | `EXIT_NOT_GIT_REPO` | Not a git repository |
| `2` | `EXIT_GH_NOT_INSTALLED` | `gh` CLI not installed |
| `3` | `EXIT_GH_NOT_AUTHENTICATED` | Not authenticated with `gh` |
| `4` | `EXIT_NO_PR_FOUND` | No open PR for current branch |
| `5` | `EXIT_FETCH_FAILED` | Failed to fetch comments from GitHub API |

---

## How It Works

1. **Validates** the environment (git repo, gh installed, gh authenticated)
2. **Detects** the current branch with `git rev-parse --abbrev-ref HEAD`
3. **Finds** the open PR with `gh pr view --json number,title,headRefName,url`
4. **Gets** the repo owner and name with `gh repo view --json owner,name`
5. **Fetches** inline review comments via `gh api repos/{owner}/{repo}/pulls/{pr}/comments`
6. **Fetches** general discussion comments via `gh api repos/{owner}/{repo}/issues/{pr}/comments`
7. **Assembles** and outputs structured JSON using `python3` for safe JSON handling

---

## Troubleshooting

**"No open PR found for current branch"**
- Check you're on a feature branch: `git branch`
- Verify a PR exists: `gh pr list`
- Ensure the PR is open (not merged/closed)

**"Not authenticated with gh CLI"**
- Run: `gh auth login`
- Follow the prompts to authenticate with GitHub

**Script produces no output**
- Run with `--verbose` to see status messages on stderr
- Check that `python3` is available: `command -v python3`
