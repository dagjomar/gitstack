#!/bin/bash
#
# Git Branch Stack Management (BSM)
#
# Usage:
#   gitstack.sh create <base_name>
#   gitstack.sh increment
#   gitstack.sh delete -f <base_name>
#   gitstack.sh delete          # <-- new shorthand: prompt to delete current branch's stack
#
# Description:
#   create      -> Creates a new branch named "<base_name>-0".
#   increment   -> Increments the current branch suffix if on "<base>-<num>".
#   delete -f   -> Force-deletes ALL local branches named "<base_name>-<num>" (checking out main or master first).
#   delete      -> Looks at the current branch to determine the stack <base>, prompts to confirm, then force-deletes.
# -----------------------------------------------------------------------------

subcommand="$1"
shift

function usage() {
  echo "Git Branch Stack Management"
  echo
  echo "Usage:"
  echo "  $0 create <base_name>"
  echo "  $0 increment"
  echo "  $0 delete -f <base_name>"
  echo "  $0 delete                (Interactively delete the current stack if on <base>-<num>)"
  echo
  echo "Commands:"
  echo "  create      Creates a new branch named '<base_name>-0'."
  echo "  increment   Increments the current branch suffix if it matches '<base>-<num>'."
  echo "  delete -f   Force-deletes ALL local branches matching '<base_name>-*'."
  echo "  delete      If on '<base_name>-<num>', prompts to confirm and force-deletes that entire stack."
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
# Checks out main/master (or detaches HEAD) first, then deletes each matching branch.
function delete_stack() {
  # Typically: delete_stack -f <base_name>
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

  echo "Forcing deletion of branches in stack '${base_name}'..."
  echo "Checking out main|master branch first."

  # Try to checkout main or master (if they exist). If neither, detach HEAD.
  if git rev-parse --verify main &>/dev/null; then
    echo " -> Trying to checkout 'main'..."
    if ! git checkout main; then
      echo "Error: Could not checkout 'main'. Aborting."
      exit 1
    fi
  elif git rev-parse --verify master &>/dev/null; then
    echo " -> Trying to checkout 'master'..."
    if ! git checkout master; then
      echo "Error: Could not checkout 'master'. Aborting."
      exit 1
    fi
  else
    echo " -> No 'main' or 'master' branch found; checking out as detached HEAD..."
    if ! git checkout --detach; then
      echo "Error: Could not detach HEAD. Aborting."
      exit 1
    fi
  fi

  # Now delete each matching branch
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

# Shorthand: "git stack delete" with no arguments
# 1. Check if current branch is a stack branch "<base>-<number>"
# 2. Prompt user for confirmation to do a force delete on that base
function delete_shorthand() {
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  # Must be on a valid branch
  if [ -z "$current_branch" ] || [ "$current_branch" == "HEAD" ]; then
    echo "Error: You are not on a valid branch (detached HEAD?)."
    exit 1
  fi

  # Must match <base>-<num> pattern
  if [[ ! "$current_branch" =~ ^(.+)-([0-9]+)$ ]]; then
    echo "Error: You are not currently on a stack branch of the form '<base>-<num>'."
    exit 1
  fi

  local base_name="${BASH_REMATCH[1]}"

  echo "You are currently on stack branch '$current_branch' (base: '$base_name')."
  read -r -p "Would you like to force-delete this entire stack? [y/N] " confirm
  case "$confirm" in
    [yY])
      delete_stack -f "$base_name"
      ;;
    *)
      echo "Aborting stack deletion."
      exit 0
      ;;
  esac
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
    # If no args, do interactive shorthand; otherwise do standard logic
    if [ $# -eq 0 ]; then
      delete_shorthand
    else
      delete_stack "$@"
    fi
    ;;
  *)
    usage
    ;;
esac
