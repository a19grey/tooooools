#!/bin/bash

# gitpush
#
# Purpose: A utility script to stage, commit, and push changes to a GitHub repository,
# automatically setting the correct user identity based on the SSH host in the remote URL.
#
# Usage examples:
#   gitpush "Initial commit"
#   gitpush "Updated README"
#
# Author: Adapted from A19grey's gitpush.sh
# Notes: Requires SSH configuration with github.com-personal and github.com-trace hosts.

# Configuration: Define personal and work user details
PERSONAL_NAME="a19grey"
PERSONAL_EMAIL="a19grey@gmail.com"
WORK_NAME="AlexKTracerMain"
WORK_EMAIL="alex@traceup.com"
SKIP_N8N_EXPORT=0

# Function to display usage information
usage() {
    printf "\nUsage: %s [--skip-n8n-export] \"commit message\"\n" "$0" >&2
    printf "  --skip-n8n-export: Skip Docker-based n8n workflow export before git actions\n" >&2
    printf "  commit message: The message for your git commit\n" >&2
    exit 1
}

# Export n8n workflows if this repo has a docker-compose n8n service.
get_n8n_data_container_path() {
    local compose_file=$1

    # Parse short-form volume mappings under services.n8n.volumes and return
    # the first container-side mount path (for example: /home/node/.n8n).
    awk '
        BEGIN {
            in_n8n = 0
            in_volumes = 0
        }

        /^[[:space:]]{2}n8n:[[:space:]]*$/ {
            in_n8n = 1
            in_volumes = 0
            next
        }

        in_n8n && /^[[:space:]]{2}[A-Za-z0-9_.-]+:[[:space:]]*$/ && $0 !~ /^[[:space:]]{2}n8n:[[:space:]]*$/ {
            exit
        }

        in_n8n && /^[[:space:]]{4}volumes:[[:space:]]*$/ {
            in_volumes = 1
            next
        }

        in_n8n && in_volumes && /^[[:space:]]{4}[A-Za-z0-9_.-]+:[[:space:]]*$/ && $0 !~ /^[[:space:]]{4}volumes:[[:space:]]*$/ {
            in_volumes = 0
        }

        in_n8n && in_volumes && /^[[:space:]]{6}-[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]{6}-[[:space:]]*/, "", line)
            count = split(line, parts, ":")

            if (count >= 2) {
                container_path = parts[2]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", container_path)
                gsub(/["'\'']/, "", container_path)

                if (container_path ~ /^\//) {
                    print container_path
                    exit
                }
            }
        }
    ' "$compose_file"
}

export_n8n_workflows_if_configured() {
    local repo_root=$1
    local compose_file="$repo_root/docker-compose.yml"
    local has_n8n_service=0
    local n8n_export_host_path="$repo_root"
    local n8n_data_container_path
    local n8n_export_container_path

    if [ ! -f "$compose_file" ]; then
        printf "\n=== No docker-compose.yml found. Skipping n8n export. ===\n" >&2
        return 0
    fi

    if rg -q '^[[:space:]]{2}n8n:[[:space:]]*$' "$compose_file"; then
        has_n8n_service=1
    fi

    if [ "$has_n8n_service" -ne 1 ]; then
        printf "\n=== docker-compose.yml found, but no n8n service. Skipping n8n export. ===\n" >&2
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        printf "\n!!! ERROR: docker is required for n8n export but is not installed !!!\n" >&2
        exit 1
    fi

    n8n_data_container_path=$(get_n8n_data_container_path "$compose_file")
    if [ -z "$n8n_data_container_path" ]; then
        printf "\n!!! ERROR: Could not detect n8n container data path from %s !!!\n" "$compose_file" >&2
        printf "Expected a volumes mapping in the n8n service (example: n8n_data:/home/node/.n8n).\n" >&2
        exit 1
    fi

    n8n_export_container_path="${n8n_data_container_path%/}/exported_workflows/"

    printf "\n=== Exporting n8n workflows to %s ===\n" "$n8n_export_host_path" >&2
    printf "=== Using n8n container data path: %s ===\n" "$n8n_data_container_path" >&2

    mkdir -p "$n8n_export_host_path"

    if ! docker compose -f "$compose_file" exec -u node n8n sh -lc \
        "rm -rf \"$n8n_export_container_path\" && mkdir -p \"$n8n_export_container_path\" && n8n export:workflow --all --backup --output=\"$n8n_export_container_path\""; then
        printf "\n!!! ERROR: n8n export command failed !!!\n" >&2
        exit 1
    fi

    if ! docker compose -f "$compose_file" cp \
        "n8n:${n8n_export_container_path}." "$n8n_export_host_path"; then
        printf "\n!!! ERROR: Failed copying exported n8n workflows to host path !!!\n" >&2
        exit 1
    fi

    printf "=== n8n workflow export completed successfully ===\n" >&2
}

# Function to commit and push changes
commit_and_push() {
    local commit_message=$1

    # Get the git repository root directory
    local repo_root=$(git rev-parse --show-toplevel)
    if [ -z "$repo_root" ]; then
        printf "\n!!! ERROR: Could not determine git repository root !!!\n" >&2
        exit 1
    fi

    # Change to the repository root directory
    printf "\n=== Changing to repository root: %s ===\n" "$repo_root" >&2
    cd "$repo_root"

    # Ensure latest n8n workflows are exported before staging git changes unless skipped.
    if [ "$SKIP_N8N_EXPORT" -eq 1 ]; then
        printf "\n=== Skipping n8n workflow export (--skip-n8n-export) ===\n" >&2
    else
        export_n8n_workflows_if_configured "$repo_root"
    fi

    # Show what will be staged
    printf "\n=== Files to be staged: ===\n" >&2
    git status

    # Add all files
    printf "\n=== Staging all changes... ===\n" >&2
    git add .

    # Show what's been staged
    printf "\n=== Staged files: ===\n" >&2
    git status --short

    # Commit with the provided message
    printf "\n=== Committing changes with message: '%s' ===\n" "$commit_message" >&2
    git commit -m "$commit_message"

    # Get current branch - using --show-current is more reliable
    CURRENT_BRANCH=$(git branch --show-current)

    # Fail if we can't determine the branch instead of defaulting to main
    if [ -z "$CURRENT_BRANCH" ]; then
        printf "\n!!! ERROR: Could not determine current branch !!!\n" >&2
        exit 1
    fi

    printf "\n=== Pushing to branch: %s ===\n" "$CURRENT_BRANCH" >&2

    # Try pushing with different strategies
    if ! git push -u origin "$CURRENT_BRANCH"; then
        printf "\n!!! Initial push failed. Trying alternative methods... !!!\n" >&2
        
        # Try pushing with the --force flag
        if ! git push -u origin "$CURRENT_BRANCH" --force; then
            printf "\n!!! Force push failed. Trying to push without verification... !!!\n" >&2
            
            # Try pushing with --no-verify
            if ! git push -u origin "$CURRENT_BRANCH" --force --no-verify; then
                printf "\n!!! ERROR: All push attempts failed !!!\n" >&2
                printf "Please check your repository and network connection.\n" >&2
                printf "You may need to push manually or in smaller commits.\n" >&2
                exit 1
            fi
        fi
    fi

    printf "\n=== Push successful! ===\n" >&2
}

# Main script execution starts here

# Parse optional flags
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-n8n-export)
            SKIP_N8N_EXPORT=1
            shift
            ;;
        --help|-h)
            usage
            ;;
        --*)
            printf "\n!!! ERROR: Unknown option: %s !!!\n" "$1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Validate command line arguments
if [ $# -lt 1 ]; then
    usage
fi

COMMIT_MESSAGE="$*"

# Validate commit message
if [ -z "$COMMIT_MESSAGE" ]; then
    printf "\n!!! ERROR: Commit message is required !!!\n" >&2
    usage
fi

# Ensure we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    printf "\n!!! ERROR: Not in a Git repository !!!\n" >&2
    exit 1
fi

# Get the remote URL for origin
remote_url=$(git remote get-url origin 2>/dev/null)
if [ -z "$remote_url" ]; then
    printf "\n!!! ERROR: No remote 'origin' configured !!!\n" >&2
    exit 1
fi

# Determine the account based on the SSH host or organization in the remote URL
case "$remote_url" in
    *github.com-personal*|*":${PERSONAL_NAME}/"*|*"github.com/${PERSONAL_NAME}/"*)
        git config user.name "$PERSONAL_NAME"
        git config user.email "$PERSONAL_EMAIL"
        printf "\n=== Using personal account: %s <%s> ===\n" "$PERSONAL_NAME" "$PERSONAL_EMAIL" >&2
        ;;
    *github.com-trace*|*tracevision*|*":${WORK_NAME}/"*|*"github.com/${WORK_NAME}/"*)
        git config user.name "$WORK_NAME"
        git config user.email "$WORK_EMAIL"
        printf "\n=== Using work account: %s <%s> ===\n" "$WORK_NAME" "$WORK_EMAIL" >&2
        ;;
    *)
        printf "\n!!! ERROR: Remote URL does not match known hosts (github.com-personal or github.com-trace) or organizations (tracevision) !!!\n" >&2
        printf "Current remote: %s\n" "$remote_url" >&2
        exit 1
        ;;
esac

# Commit and push changes
commit_and_push "$COMMIT_MESSAGE"

printf "\n=== Successfully pushed to %s ===\n" "$remote_url" >&2
