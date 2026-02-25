#!/bin/bash

# git-fetch-filter
#
# In large repos with thousands of remote branches, "git fetch" tracks everything,
# bloating local storage and slowing operations. It also makes Git GUIs difficult
# since your branches get buried under a sea of remote refs. This is the "set it
# and forget it" solution — it fetches only the remote-tracking refs that correspond
# to your local branches (plus the default branch), keeping your local environment lean.
#
# Can be run ad-hoc or on a schedule via the built-in cron setup (-c).

# Configurable via environment variables:
#   GIT_REPO_DIR      Path to the git repo (default: current directory)
#   GIT_REMOTE        Remote name (default: origin)
#   GIT_DEFAULT_BRANCH  Branch to always track (default: auto-detected from remote HEAD)
GIT_REPO_DIR="${GIT_REPO_DIR:-.}"
GIT_REMOTE="${GIT_REMOTE:-origin}"

set -e

displayUsage() {
    echo "In large repos with thousands of remote branches, 'git fetch' tracks everything,"
    echo "bloating local storage and slowing operations. It also makes Git GUIs difficult"
    echo "to use, since your branches get buried under a sea of remote refs you don't need."
    echo ""
    echo "You can solve this by manually managing fetch refspecs in your git config,"
    echo "but that requires updating them every time you create or delete a branch. This"
    echo "script is the 'set it and forget it' solution — it only fetches remote refs for"
    echo "branches you have checked out locally (plus the default branch), since those are"
    echo "the only ones you need to be up-to-date on."
    echo ""
    echo "If this is your first time using this script, run with -r to clean up your"
    echo "existing remote-tracking refs before switching to filtered fetches."
    echo ""
    echo "Usage: $(basename "$0") [-r] [-l logfile] [-t] [-c] [-h]"
    echo "  -h    Display this message."
    echo "  -c    Install (or update) a cron job for this script. Prompts for frequency."
    echo "  -l    Append output to a log file (useful for cron)."
    echo "  -t    Show the last 100 lines of the log file configured in the cron job."
    echo "  -r    Refreshes all current remote-tracking _refs_ for the configured remote before fetching"
    echo "        only relevant ones. This cleans up stale tracking _refs_. NOTE: This only affects local"
    echo "        remote-tracking _refs_ (e.g. origin/*), not your local branches or any remote branches."
    echo ""
    echo "Environment variables:"
    echo "  GIT_REPO_DIR         Path to the git repo (default: current directory)"
    echo "  GIT_REMOTE           Remote name (default: origin)"
    echo "  GIT_DEFAULT_BRANCH   Branch to always track (default: auto-detected from remote HEAD)"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                     # Fetch refs for local branches only"
    echo "  $(basename "$0") -r                   # Refresh all tracking refs, then fetch relevant ones"
    echo "  $(basename "$0") -c                   # Set up a cron job (interactive)"
    echo "  $(basename "$0") -t                   # View recent log output"
    echo "  GIT_REPO_DIR=~/git/myrepo $(basename "$0")  # Run against a specific repo"
}

# Resolve the absolute path to this script for use in cron entries
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

setupCron() {
    # Prompt for repo directory
    local default_repo_dir="."
    printf "Path to git repo [%s]: " "$default_repo_dir"
    read -r repo_dir
    if [[ -z "$repo_dir" ]]; then
        repo_dir="$default_repo_dir"
    fi
    # Expand ~ since tilde expansion doesn't happen inside quotes from read
    repo_dir="${repo_dir/#\~/$HOME}"
    # Resolve to absolute path
    repo_dir="$(cd "$repo_dir" 2>/dev/null && pwd)" || { echo "Error: Directory not found: $repo_dir"; exit 1; }

    # Prompt for remote name
    printf "Remote name [origin]: "
    read -r remote_name
    if [[ -z "$remote_name" ]]; then
        remote_name="origin"
    fi

    # Prompt for default branch
    local detected_branch
    detected_branch=$(git -C "$repo_dir" remote show "$remote_name" 2>/dev/null | sed -n 's/.*HEAD branch: //p')
    local branch_default="${detected_branch:-dev}"
    printf "Default branch to always track [%s]: " "$branch_default"
    read -r default_branch
    if [[ -z "$default_branch" ]]; then
        default_branch="$branch_default"
    fi

    # Use the repo directory basename to create a unique cron tag
    local repo_name
    repo_name="$(basename "$repo_dir")"
    local cron_tag="# git-fetch-filter:$repo_name"

    echo ""
    echo "How often should this run?"
    echo "  1) Every 30 minutes"
    echo "  2) Every hour"
    echo "  3) Every 2 hours"
    echo "  4) Every 4 hours"
    echo "  5) Custom (enter minutes, minimum 30)"
    printf "Choose [1-5]: "
    read -r choice

    local schedule
    case "$choice" in
        1) schedule="*/30 * * * *" ;;
        2) schedule="0 * * * *" ;;
        3) schedule="0 */2 * * *" ;;
        4) schedule="0 */4 * * *" ;;
        5)
            printf "Enter interval in minutes (minimum 30): "
            read -r minutes
            if ! [[ "$minutes" =~ ^[0-9]+$ ]] || [[ "$minutes" -lt 30 ]]; then
                echo "Error: Must be a number, 30 or greater."
                exit 1
            fi
            if [[ "$minutes" -lt 60 ]]; then
                schedule="*/$minutes * * * *"
            else
                local hours=$(( minutes / 60 ))
                schedule="0 */$hours * * *"
            fi
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac

    # Prompt for log file name
    local default_log="${HOME}/logs/git-fetch-filter-${repo_name}.log"
    echo ""
    echo "Where should logs be written? The file will be created if it doesn't exist."
    printf "Log file path [%s]: " "$default_log"
    read -r log_file
    if [[ -z "$log_file" ]]; then
        log_file="$default_log"
    fi
    log_file="${log_file/#\~/$HOME}"

    local env_prefix="GIT_REPO_DIR=$repo_dir GIT_REMOTE=$remote_name GIT_DEFAULT_BRANCH=$default_branch"
    local cron_cmd="$schedule $env_prefix $SCRIPT_PATH -l $log_file $cron_tag"

    # Remove any existing entry for this script, then add the new one
    local existing_crontab
    existing_crontab=$(crontab -l 2>/dev/null || true)
    local new_crontab
    new_crontab=$(echo "$existing_crontab" | grep -v "$cron_tag" || true)

    echo "$new_crontab" | { cat; echo "$cron_cmd"; } | crontab -

    echo ""
    echo "Cron job installed:"
    echo "  $cron_cmd"
    echo ""
    echo "Log output: $log_file"
}

# Parse optional flags
REFRESH_ALL_REFS=0
LOG_FILE=""
while getopts "rl:tch" opt; do
    case "$opt" in
        r)
            REFRESH_ALL_REFS=1
            ;;
        l)
            LOG_FILE="$OPTARG"
            ;;
        t)
            local_cron_tag="# git-fetch-filter:"
            cron_entries=()
            while IFS= read -r line; do
                cron_entries+=("$line")
            done < <(crontab -l 2>/dev/null | grep "$local_cron_tag")
            if [[ ${#cron_entries[@]} -eq 0 ]]; then
                echo "Error: No cron jobs found. Run with -c to set one up."
                exit 1
            fi
            if [[ ${#cron_entries[@]} -eq 1 ]]; then
                cron_log=$(echo "${cron_entries[0]}" | sed -n 's/.*-l \([^ ]*\).*/\1/p')
            else
                echo "Multiple cron jobs found:"
                for i in "${!cron_entries[@]}"; do
                    entry_name=$(echo "${cron_entries[$i]}" | sed -n 's/.*# git-fetch-filter://p')
                    echo "  $((i+1))) $entry_name"
                done
                printf "Choose [1-%d]: " "${#cron_entries[@]}"
                read -r pick
                if ! [[ "$pick" =~ ^[0-9]+$ ]] || [[ "$pick" -lt 1 ]] || [[ "$pick" -gt ${#cron_entries[@]} ]]; then
                    echo "Invalid choice."
                    exit 1
                fi
                cron_log=$(echo "${cron_entries[$((pick-1))]}" | sed -n 's/.*-l \([^ ]*\).*/\1/p')
            fi
            if [[ ! -f "$cron_log" ]]; then
                echo "Error: Log file not found: $cron_log"
                echo "The cron job may not have run yet."
                exit 1
            fi
            tail -n 100 "$cron_log"
            exit 0
            ;;
        c)
            setupCron
            exit 0
            ;;
        h)
            displayUsage
            exit 0
            ;;
        *)
            displayUsage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# If a log file is specified, rotate if needed and redirect all output to it
MAX_LOG_LINES=10000
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    # Only rotate if the file contains our "---" divider (avoid truncating unrelated files if one is accidentally passed in)
    if [[ -f "$LOG_FILE" ]] && grep -q "^---$" "$LOG_FILE" && [[ $(wc -l < "$LOG_FILE") -gt $MAX_LOG_LINES ]]; then
        tmp=$(mktemp)
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
    fi
    exec >> "$LOG_FILE" 2>&1
fi

# Add divider and timestamp when running non-interactively (cron / log file)
if [[ -n "$LOG_FILE" ]] || ! [[ -t 1 ]]; then
    echo "---"
    date
fi

cd "$GIT_REPO_DIR" || { echo "Error: $GIT_REPO_DIR not found"; exit 1; }

# Verify we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: $GIT_REPO_DIR is not a git repository"
    exit 1
fi

# Auto-detect the default branch from the remote if not set
if [[ -z "${GIT_DEFAULT_BRANCH:-}" ]]; then
    GIT_DEFAULT_BRANCH=$(git remote show "$GIT_REMOTE" 2>/dev/null | sed -n 's/.*HEAD branch: //p')
    if [[ -z "$GIT_DEFAULT_BRANCH" ]]; then
        echo "Warning: Could not detect default branch from $GIT_REMOTE, falling back to 'dev'"
        GIT_DEFAULT_BRANCH="dev"
    fi
fi

# Refresh all remote-tracking refs (this does not delete any remote branches)
if [[ $REFRESH_ALL_REFS -eq 1 ]]; then
    echo "Refreshing all local remote-tracking refs for $GIT_REMOTE. This may take a while..."
    for rb in $(git branch -r | grep -v '\->' | grep "^  $GIT_REMOTE/" | sed "s|  $GIT_REMOTE/||"); do
        git branch -rd "$GIT_REMOTE/$rb" 2>/dev/null || true
    done
fi

# Get all local branch names
local_branches=$(git branch --format="%(refname:short)")

# Ensure the default branch is included even if it isn't a local branch
branches_to_track=$(printf '%s\n%s' "$local_branches" "$GIT_DEFAULT_BRANCH")

# Remove duplicates and sort the list
branches_to_track=$(echo "$branches_to_track" | sort -u)

echo "Retrieving list of local branches with remote refs on $GIT_REMOTE..."

# Get a single list of remote branch names from the remote
remote_branches=$(git ls-remote --heads "$GIT_REMOTE" | sed 's#.*refs/heads/##')

# Build an array of refspecs for branches that exist on remote
refspecs=()
for branch in $branches_to_track; do
    if echo "$remote_branches" | grep -qx "$branch"; then
        echo "Found remote ref for '$branch'"
        refspecs+=( "+refs/heads/$branch:refs/remotes/$GIT_REMOTE/$branch" )
    fi
done

# Fetch all remote-tracking refs for the selected branches at once.
if [[ ${#refspecs[@]} -gt 0 ]]; then
    echo "Fetching relevant refs from $GIT_REMOTE..."
    git fetch "$GIT_REMOTE" "${refspecs[@]}"
else
    echo "No branches to fetch."
fi

echo "Done."
