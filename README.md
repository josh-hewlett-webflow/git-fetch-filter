# git-fetch-filter

In large repos with thousands of remote branches, `git fetch` tracks everything — bloating local storage and slowing operations. This script only fetches remote refs for branches you have checked out locally (plus the default branch), since those are the only ones you need to be up-to-date on.

## Quick Start

```bash
# 1. Download and make executable
curl -fsSL https://raw.githubusercontent.com/josh-hewlett-webflow/git-fetch-filter/main/git-fetch-filter.sh -o ~/bin/git-fetch-filter
chmod +x ~/bin/git-fetch-filter

# 2. Clean up existing tracking refs (recommended for first run)
cd ~/git/your-repo
git-fetch-filter -r

# 3. Set up automatic fetching via cron
git-fetch-filter -c
```

## Usage

```
git-fetch-filter [-r] [-l logfile] [-t] [-c] [-h]
```

| Flag | Description |
|------|-------------|
| `-h` | Display help message |
| `-r` | Refresh all remote-tracking refs before fetching relevant ones. Recommended on first run to clean up stale refs. Only affects local tracking refs — not your local branches or remote branches. |
| `-c` | Set up (or update) a cron job. Walks you through frequency, repo path, remote, default branch, and log file. Supports multiple repos. |
| `-t` | View the last 100 lines of the cron log file. If multiple repos are configured, prompts you to choose. |
| `-l <file>` | Append output to a log file. Used internally by the cron job. |

## Environment Variables

All optional — sensible defaults are provided.

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_REPO_DIR` | `.` (current directory) | Path to the git repo |
| `GIT_REMOTE` | `origin` | Remote name |
| `GIT_DEFAULT_BRANCH` | Auto-detected from remote HEAD | Branch to always track |

```bash
# Example: run against a specific repo with a non-default remote
GIT_REPO_DIR=~/git/my-repo GIT_REMOTE=upstream git-fetch-filter
```

## Cron Setup

The `-c` flag walks you through an interactive setup:

```
$ git-fetch-filter -c
Path to git repo [.]: ~/git/webflow
Remote name [origin]:
Default branch to always track [dev]:

How often should this run?
  1) Every 30 minutes
  2) Every hour
  3) Every 2 hours
  4) Every 4 hours
  5) Custom (enter minutes, minimum 30)
Choose [1-5]: 2
Where should logs be written? The file will be created if it doesn't exist.
Log file path [/Users/you/logs/git-fetch-filter-webflow.log]:

Cron job installed:
  0 * * * * GIT_REPO_DIR=/Users/you/git/webflow GIT_REMOTE=origin GIT_DEFAULT_BRANCH=dev /Users/you/bin/git-fetch-filter -l /Users/you/logs/git-fetch-filter-webflow.log # git-fetch-filter:webflow
```

Running `-c` again for the same repo updates the existing entry. Running it for a different repo adds a separate entry. Log files are automatically rotated to prevent unbounded growth.

## How It Works

1. Reads your local branch names (`git branch`)
2. Queries the remote for its branch list (`git ls-remote --heads`)
3. Builds refspecs for the intersection + the default branch
4. Runs a single `git fetch` with only those refspecs

This replaces the default `git fetch` behavior of `+refs/heads/*:refs/remotes/origin/*` (fetch everything) with a targeted fetch of only what you're working on.
