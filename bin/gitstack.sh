#!/bin/bash
#
# Git Branch Stack Management (BSM)
#
# Usage:
#   gitstack.sh create <base_name>
#   gitstack.sh increment
#   gitstack.sh delete -f <base_name>
#
# Description:
#   create      -> Creates a new branch named "<base_name>-0".
#   increment   -> Increments the current branch suffix if on "<base>-<num>".
#   delete -f   -> Force-deletes ALL local branches named "<base_name>-<num>".
#                  Will first check out main/master (or detach HEAD if none exist).
# ------------------------------------------------------------------------------

subcommand="$1"
shift

function usage() {
  echo "Git Branch Stack Management"
  echo
  echo "Usage:"
  echo "  $0 create <base_name>"
  echo "  $0 increment"
  echo "  $0 delete -f <base_name>"
  echo
  echo "Commands:"
  echo "  create      Creates a new branch named '<base_name>-0'."
  echo "  increment   Increments the current branch suffix if the name matches '<base>-<num>'."
  echo "  delete -f   Force-deletes ALL local branches matching '<base_name>-*'."
  echo "             Checks out main/master (or detaches HEAD) first to avoid conflicts."
  exit 1
}

# Create a new branch: "<base_name>-0"
function create_branch() {
  local base_name="$1"

  if [ -z "$base_name" ]; then
    echo "Error: Missing <base_name> for 'create'."
    usage
  fi

  local new_branch="${base_name}-0"

  # Check if branch already exists
  if git rev-parse --verify "$new_branch" &>/dev/null; then
    echo "Error: Branch '$new_branch' already exists. Aborting."
    exit 1
  fi

  echo "Creating branch: $new_branch"
  if ! git checkout -b "$new_branch"; then
    echo "Error: Failed to create branch '$new_branch'."
    exit 1
  fi

  echo "Branch '$new_branch' successfully created and checked out."
}

# Increment the current branch suffix: "<base>-<num>" -> "<base>-<num+1>"
function increment_branch() {
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  if [ -z "$current_branch" ] || [ "$current_branch" == "HEAD" ]; then
    echo "Error: You are not on a valid branch (detached HEAD?)."
    exit 1
  fi

  if [[ "$current_branch" =~ ^(.+)-([0-9]+)$ ]]; then
    local base="${BASH_REMATCH[1]}"
    local number="${BASH_REMATCH[2]}"
    local new_number=$((number + 1))
    local new_branch="${base}-${new_number}"

    # Check if new branch already exists
    if git rev-parse --verify "$new_branch" &>/dev/null; then
      echo "Error: Branch '$new_branch' already exists. Aborting."
      exit 1
    fi

    echo "Current branch: $current_branch"
    echo "Incrementing to: $new_branch"

    if ! git checkout -b "$new_branch"; then
      echo "Error: Failed to create branch '$new_branch'."
      exit 1
    fi

    echo "Branch '$new_branch' successfully created and checked out."
  else
    echo "Error: Current branch '$current_branch' does not match '<base>-<number>' pattern."
    exit 1
  fi
}

# Force-delete all local branches in the stack "<base_name>-*"
# Will check out main/master (or detach HEAD) first, then delete each matching branch.
function delete_stack() {
  # We expect: delete -f <base_name>
  local force_flag="$1"
  local base_name="$2"

  # Validate inputs
  if [ "$force_flag" != "-f" ] && [ "$force_flag" != "--force" ]; then
    echo "Error: Missing '-f' to force-delete the stack."
    usage
  fi

  if [ -z "$base_name" ]; then
    echo "Error: Missing <base_name> for 'delete'."
    usage
  fi

  # Find all matching branches of the form "<base_name>-*"
  local matching_branches
  matching_branches=$(git branch --list "${base_name}-*" | sed 's/^[* ]*//')

  if [ -z "$matching_branches" ]; then
    echo "No branches found matching '${base_name}-*'. Nothing to delete."
    return 0
  fi

  echo "Forcing deletion of branches in stack '${base_name}':"
  echo "Checking out main|master branch first"

  # Try to checkout main or master (if they exist). If neither, detach HEAD.
  if git rev-parse --verify main &>/dev/null; then
    echo "Trying to checkout 'main'..."
    if ! git checkout main; then
      echo "Error: Could not checkout 'main'. Aborting."
      exit 1
    fi
  elif git rev-parse --verify master &>/dev/null; then
    echo "Trying to checkout 'master'..."
    if ! git checkout master; then
      echo "Error: Could not checkout 'master'. Aborting."
      exit 1
    fi
  else
    echo "No 'main' or 'master' branch found; checking out as detached HEAD..."
    if ! git checkout --detach; then
      echo "Error: Could not detach HEAD. Aborting."
      exit 1
    fi
  fi

  # Now delete all matching branches
  echo "Deleting branches:"
  while read -r branch_name; do
    if [ -n "$branch_name" ]; then
      echo "  - $branch_name"
      if ! git branch -D "$branch_name"; then
        echo "Error: Failed to delete branch '$branch_name'."
        exit 1
      fi
    fi
  done <<< "$matching_branches"

  echo "All matching '${base_name}-*' branches have been force-deleted."
}

# Subcommand dispatch
case "$subcommand" in
  create)
    create_branch "$@"
    ;;
  increment)
    increment_branch
    ;;
  delete)
    delete_stack "$@"
    ;;
  *)
    usage
    ;;
esac
