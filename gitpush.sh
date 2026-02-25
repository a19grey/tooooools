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

# Function to display usage information
usage() {
    printf "\nUsage: %s \"commit message\"\n" "$0" >&2
    printf "  commit message: The message for your git commit\n" >&2
    exit 1
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
    *github.com-personal*)
        git config user.name "$PERSONAL_NAME"
        git config user.email "$PERSONAL_EMAIL"
        printf "\n=== Using personal account: %s <%s> ===\n" "$PERSONAL_NAME" "$PERSONAL_EMAIL" >&2
        ;;
    *github.com-trace*|*tracevision*)
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