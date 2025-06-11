#!/bin/bash
#
# Git Branch Stack Management (BSM)
#
# Usage:
#   gitstack.sh create <base_name>
#   gitstack.sh increment
#   gitstack.sh delete -f <base_name>
#   gitstack.sh delete          # <-- new shorthand: prompt to delete current branch's stack
#   gitstack.sh list           # <-- interactive stack browser with preview
#   gitstack.sh status [stack] # <-- show health status of specified stack or all stacks
#   gitstack.sh fix [stack]    # <-- fix an unhealthy stack by rebasing divergent branches
#   gitstack.sh prev          # <-- checkout previous branch in stack (e.g. feature-2 -> feature-1)
#   gitstack.sh next          # <-- checkout next branch in stack (e.g. feature-2 -> feature-3)
#   gitstack.sh push [stack]  # <-- force-push all branches in a stack to remote
#   gitstack.sh pr [gh-args]  # <-- create GitHub PR targeting correct parent branch
#
# Description:
#   create      -> Creates a new branch named "<base_name>-0".
#   increment   -> Increments the current branch suffix if on "<base>-<num>".
#   delete -f   -> Force-deletes ALL local branches named "<base_name>-<num>" (checking out main or master first).
#   delete      -> Looks at the current branch to determine the stack <base>, prompts to confirm, then force-deletes.
#   list        -> Interactive browser for stacks with branch details preview.
#   status      -> Shows health status of all stacks (or specified stack if provided).
#   fix         -> Fix an unhealthy stack by rebasing divergent branches.
#   prev        -> Checkout previous branch in stack (e.g. feature-2 -> feature-1).
#   next        -> Checkout next branch in stack (e.g. feature-2 -> feature-3).
#   push        -> Force-push all branches in a stack to remote (uses current stack if none specified).
#   pr          -> Create GitHub PR targeting correct parent branch in stack.
# -----------------------------------------------------------------------------

function usage() {
  echo "Git Branch Stack Management"
  echo
  echo "Usage:"
  echo "  $0 create <base_name>"
  echo "  $0 increment"
  echo "  $0 delete -f <base_name>"
  echo "  $0 delete                (Interactively delete the current stack if on <base>-<num>)"
  echo "  $0 list                  (Interactive stack browser with branch preview)"
  echo "  $0 status [stack]        (Show health status of specified stack or all stacks)"
  echo "  $0 fix [stack]           (Fix an unhealthy stack by rebasing divergent branches)"
  echo "  $0 prev                  (Checkout previous branch in stack)"
  echo "  $0 next                  (Checkout next branch in stack)"
  echo "  $0 push [stack]          (Force-push all branches in a stack to remote)"
  echo "  $0 pr [gh-args]          (Create GitHub PR targeting correct parent branch)"
  echo
  echo "Commands:"
  echo "  create      Creates a new branch named '<base_name>-0'."
  echo "  increment   Increments the current branch suffix if it matches '<base>-<num>'."
  echo "  delete -f   Force-deletes ALL local branches matching '<base_name>-*'."
  echo "  delete      If on '<base_name>-<num>', prompts to confirm and force-deletes that entire stack."
  echo "  list        Interactive browser for stacks with branch details preview."
  echo "  status      Shows health status of all stacks (or specified stack if provided)."
  echo "  fix         Fix an unhealthy stack by rebasing divergent branches."
  echo "  prev        Checkout previous branch in stack (e.g. feature-2 -> feature-1)."
  echo "  next        Checkout next branch in stack (e.g. feature-2 -> feature-3)."
  echo "  push        Force-push all branches in a stack to remote. Uses current stack if none specified."
  echo "  pr          Create GitHub PR targeting correct parent branch. Passes additional args to 'gh pr create'."
  exit 1
}

# Create a new branch: "<base_name>-0"
function create_branch() {
  local base_name="$1"
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  # If no base name provided, try to convert current branch
  if [ -z "$base_name" ]; then
    # Check if already on a stack branch
    if get_stack_info; then
      echo "Already on a stack branch '$current_branch'."
      exit 0
    fi
    
    # Prompt for confirmation
    read -r -p "Already on a branch named $current_branch. Create a stack from this branch? [Y/n] " response
    response=${response:-y}  # Default to yes
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo "Conversion cancelled."
      exit 0
    fi
    
    # Create new stack branch by renaming current branch
    local new_branch="${current_branch}-0"
    
    # Check if the new branch already exists
    if git rev-parse --verify "$new_branch" &>/dev/null; then
      echo "Error: Branch '$new_branch' already exists. Aborting."
      exit 1
    fi
    
    echo "Converting branch to stack branch: $new_branch"
    if ! git branch -m "$new_branch"; then
      echo "Error: Failed to rename branch to '$new_branch'."
      exit 1
    fi
    
    echo "Branch successfully converted to '$new_branch'."
    return 0
  fi

  # Original functionality for when base_name is provided
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

# Returns the base name and number of the current branch if it's part of a stack
# Usage: if get_stack_info; then echo "Base: $STACK_BASE, Number: $STACK_NUM"; fi
get_stack_info() {
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  
  if [[ $current_branch =~ ^(.+)-([0-9]+)$ ]]; then
    STACK_BASE="${BASH_REMATCH[1]}"
    STACK_NUM="${BASH_REMATCH[2]}"
    return 0  # Success
  else
    STACK_BASE=""
    STACK_NUM=""
    return 1  # Not a stack branch
  fi
}

# Gets all branches belonging to a stack
# Usage: get_stack_branches "base-name"
get_stack_branches() {
  local base_name="$1"
  git branch --list "${base_name}-[0-9]*" | sed 's/^[* ]*//'
}

# Modify increment_stack to use the new function
increment_stack() {
  if get_stack_info; then
    local new_num=$((STACK_NUM + 1))
    local new_branch="${STACK_BASE}-${new_num}"
    git checkout -b "$new_branch"
    echo "Branch '$new_branch' successfully created and checked out."
  else
    echo "Error: Current branch is not part of a stack (should match '<base>-<number>' pattern)."
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
    # Try to get base name from current branch if none provided
    if get_stack_info; then
      base_name="$STACK_BASE"
    else
      echo "Error: Missing <base_name> for 'delete' and not currently on a stack branch."
      usage
    fi
  fi

  # Find all matching branches of the form "<base_name>-*"
  local matching_branches
  matching_branches=$(get_stack_branches "$base_name")

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

# Lists all stacks with an interactive selector
# Shows branch details in the preview window
function list_stacks() {
  # Check for fzf
  if ! command -v fzf >/dev/null 2>&1; then
    echo "Error: This feature requires 'fzf' to be installed."
    echo
    echo "To install fzf:"
    echo "  Homebrew (macOS): brew install fzf"
    echo "  Ubuntu/Debian:   sudo apt-get install fzf"
    echo "  Other:          Visit https://github.com/junegunn/fzf#installation"
    exit 1
  fi

  # Create temp files with unique but consistent names for this session
  local temp_dir="/tmp/gitstack_$$"
  mkdir -p "$temp_dir"
  local branch_list="$temp_dir/branches"
  local preview_script="$temp_dir/preview"
  local action_script="$temp_dir/action"

  # Get all branches that match our stack pattern
  local all_branches
  all_branches=$(git branch --format='%(refname:short)' | grep -E '^.+-[0-9]+$' || true)
  
  if [ -z "$all_branches" ]; then
    rm -rf "$temp_dir"
    echo "No stack branches found."
    exit 0
  fi

  # Extract unique stack base names and add health status
  local stack_bases
  stack_bases=$(echo "$all_branches" | sed -E 's/-[0-9]+$//' | sort -u | while read -r base; do
    health_status=$(check_stack_health "$base" >/dev/null 2>&1 && echo "✅" || echo "⚠️ ")
    echo "$base $health_status"
  done)

  # Create a temporary preview script
  cat > "$preview_script" << 'EOF'
#!/bin/bash
input="$1"
base_name="${input%% *}"  # Just take everything before the first space
mode="${2:-normal}"  # Can be 'normal' or 'rebase'

if [ "$mode" = "rebase" ]; then
  echo -e "\033[1;34mRebase Options for Stack: $base_name\033[0m\n"
  echo -e "\033[1;33mAvailable Actions:\033[0m"
  echo -e "  \033[32m1\033[0m: Rebase branch stack (with update-refs)"
  echo -e "\n\033[90mPress a number to select an action, or Escape to cancel\033[0m"
else
  echo -e "\033[1;34mStack: $base_name\033[0m\n"
  echo -e "\033[1;33mBranch Actions:\033[0m"
  echo -e "  \033[36mEnter\033[0m: Checkout selected branch"
  echo -e "  \033[36mCtrl-D\033[0m: Delete selected branch"
  echo -e "  \033[36mCtrl-R\033[0m: Show rebase options\n"
  echo -e "\033[1;33mStack Branches:\033[0m"

  # Get and display branches
  while read -r branch; do
    if [ "$branch" = "$(git rev-parse --abbrev-ref HEAD)" ]; then
      echo -e "\033[32m→ $branch\033[0m"
    else
      echo -e "  $branch"
    fi
    git log -1 --color=always --format="    %h %s (%cr) <%an>" "$branch"
    echo
  done < <(git branch --list "$base_name-[0-9]*" --format="%(refname:short)" | sort -V)
fi
EOF
  chmod +x "$preview_script"

  # Create a temporary rebase selector script
  local rebase_selector="$temp_dir/rebase_selector"
  cat > "$rebase_selector" << 'EOF'
#!/bin/bash
branch="$1"

echo -e "\033[1;34mRebase Target: $branch\033[0m\n"
echo -e "This will rebase the current branch and all its descendants onto \033[1;32m$branch\033[0m"
echo -e "using git's update-refs feature to maintain the stack structure.\n"
echo -e "\033[90mPress Enter to confirm, or Ctrl-C to cancel\033[0m"
EOF
  chmod +x "$rebase_selector"

  # Create a temporary branch selector script
  local branch_selector="$temp_dir/branch_selector"
  cat > "$branch_selector" << EOF
#!/bin/bash
branch="$1"
base_name="${1%-[0-9]*}"  # Extract base name from branch

echo -e "\033[1;34m$branch\033[0m"
git log -1 --color=always --format="    %h %s (%cr) <%an>" "$branch"
echo
EOF
  chmod +x "$branch_selector"

  # Create a temporary action script for branch operations
  cat > "$action_script" << 'EOF'
#!/bin/bash
action="$1"
input="$2"
base_name="${input%% *}"  # Just take everything before the first space
key="${3:-}"  # Optional key for rebase actions

case "$action" in
  "checkout")
    # Show selector for branch to checkout
    echo -e "\033[1;33mSelect branch to checkout:\033[0m"
    selected_branch=$(SHELL=/bin/bash fzf --ansi \
      --preview "$branch_selector {}" \
      --preview-window="right:65%:wrap" \
      --header="Select branch to checkout (Enter to confirm, Ctrl-C to cancel)" \
      < <(git branch --list "$base_name-[0-9]*" --format="%(refname:short)" | sort -V))

    if [ -n "$selected_branch" ]; then
      git checkout "$selected_branch"
    fi
    ;;
  "delete")
    # Get the latest branch in the stack
    latest_branch=$(git branch --list "$base_name-[0-9]*" --format="%(refname:short)" | sort -V | tail -n1)
    git branch -D "$latest_branch"
    ;;
  "rebase")
    if [ "$key" = "1" ]; then
      # Get the latest branch in the stack
      latest_branch=$(git branch --list "$base_name-[0-9]*" --format="%(refname:short)" | sort -V | tail -n1)
      
      # Check if we're on the latest branch
      current_branch=$(git rev-parse --abbrev-ref HEAD)
      if [ "$current_branch" != "$latest_branch" ]; then
        echo "Checking out latest branch '$latest_branch' first..."
        if ! git checkout "$latest_branch"; then
          echo "Error: Failed to checkout latest branch"
          exit 1
        fi
      fi

      # Show selector for base branch
      echo -e "\033[1;33mSelect branch to rebase onto:\033[0m"
      base_branch=$(SHELL=/bin/bash fzf --ansi \
        --preview "$(realpath "$rebase_selector") {}" \
        --preview-window="right:65%:wrap" \
        --header="Select base branch for rebase (Enter to confirm, Ctrl-C to cancel)" \
        < <(echo "main"; git branch --list "$base_name-[0-9]*" --format="%(refname:short)" | sort -V | while read -r b; do
          if [ "$b" != "$latest_branch" ]; then
            echo "$b"
          fi
        done))

      if [ -n "$base_branch" ]; then
        # Get current branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        
        # Try a dry-run rebase to check for conflicts
        if git merge-base --is-ancestor "$base_branch" "$current_branch"; then
          echo "Already up to date with $base_branch"
          exit 0
        fi
        
        if git rebase --no-ff --dry-run "$base_branch" &>/dev/null; then
          # No conflicts expected, do a normal rebase
          echo "No conflicts detected, performing rebase with update-refs..."
          git rebase "$base_branch" --update-refs
        else
          # Conflicts expected, use interactive mode
          echo "Potential conflicts detected, starting interactive rebase..."
          git rebase -i "$base_branch" --update-refs
        fi
      fi
    fi
    ;;
esac
EOF
  chmod +x "$action_script"

  # Use fzf to select a stack with interactive preview
  local selected
  selected=$(echo "$stack_bases" | \
    fzf --ansi \
        --no-mouse \
        --preview "$preview_script {}" \
        --preview-window='right:65%:wrap' \
        --bind 'ctrl-p:toggle-preview' \
        --bind 'right:preview-down,left:preview-up' \
        --bind "enter:execute:$action_script checkout {}" \
        --bind "ctrl-d:execute:$action_script delete {}" \
        --bind "ctrl-r:change-preview($preview_script {} rebase)" \
        --bind "1:execute:$action_script rebase {} 1" \
        --bind "esc:change-preview($preview_script {} normal)" \
        --header "Stack Browser
→ Use arrows to navigate
→ Right/Left to scroll preview
→ Enter to checkout latest branch
→ Ctrl-D to delete latest branch
→ Ctrl-R to show rebase options
→ Ctrl-P to toggle preview
→ Ctrl-C to exit")

  # Clean up
  rm -rf "$temp_dir"

  # If a stack was selected, show success message
  if [ -n "$selected" ]; then
    echo "Selected stack: $selected"
  fi
}

# Check the health of a stack by verifying that each branch is based on its parent
# Returns 0 if healthy, 1 if needs attention
# Usage: check_stack_health "base-name"
check_stack_health() {
  local base_name="$1"
  local branches
  local prev_branch=""
  local current_branch
  local temp_file
  local result=0
  
  # Create temporary file
  temp_file=$(mktemp)
  
  # Get all branches in the stack, sorted by number
  branches=$(git branch --list "${base_name}-[0-9]*" --format="%(refname:short)" | sort -V)
  
  if [ -z "$branches" ]; then
    echo "No branches found in stack '$base_name'"
    rm -f "$temp_file"
    return 1
  fi

  # For the first branch, check if it's based on main
  first_branch=$(echo "$branches" | head -n1)
  if ! git merge-base --is-ancestor main "$first_branch" 2>/dev/null; then
    echo "$first_branch needs rebase onto main"
    rm -f "$temp_file"
    return 1
  fi

  # Save remaining branches to temp file
  echo "$branches" | tail -n +2 > "$temp_file"

  # Check each subsequent branch is based on its parent
  prev_branch="$first_branch"
  while read -r branch; do
    if ! git merge-base --is-ancestor "$prev_branch" "$branch" 2>/dev/null; then
      echo "$branch needs rebase onto $prev_branch"
      result=1
      break
    fi
    prev_branch="$branch"
  done < "$temp_file"

  # Clean up
  rm -f "$temp_file"

  if [ $result -eq 0 ]; then
    echo "Stack '$base_name' is healthy"
  fi
  return $result
}

# Get a one-line health status for a stack
# Returns: "healthy" or "needs rebase"
# Usage: status=$(get_stack_health_status "base-name")
get_stack_health_status() {
  local base_name="$1"
  if check_stack_health "$base_name" >/dev/null 2>&1; then
    echo "healthy"
  else
    echo "needs rebase"
  fi
}

# Show health status of specified stack or all stacks
function show_stack_status() {
  local stack_name="$1"
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  # If no stack specified, show status for all stacks
  if [ -z "$stack_name" ]; then
    # Get all stack bases
    local stack_bases
    stack_bases=$(git branch --format='%(refname:short)' | grep -E '^.+-[0-9]+$' | sed -E 's/-[0-9]+$//' | sort -u)
    
    if [ -z "$stack_bases" ]; then
      echo "No stacks found."
      exit 0
    fi

    # Show status for each stack
    local first=true
    while read -r base; do
      if [ "$first" = true ]; then
        first=false
      else
        echo
      fi
      show_single_stack_status "$base" "$current_branch"
    done <<< "$stack_bases"
  else
    show_single_stack_status "$stack_name" "$current_branch"
  fi
}

# Helper function to show status of a single stack
function show_single_stack_status() {
  local stack_name="$1"
  local current_branch="$2"

  # Get all branches in the stack
  local branches
  branches=$(get_stack_branches "$stack_name")
  if [ -z "$branches" ]; then
    echo "Error: No branches found in stack '$stack_name'"
    return 1
  fi

  # Show stack info
  echo "Stack: $stack_name"
  echo "Branches:"
  while read -r branch; do
    if [ "$branch" = "$current_branch" ]; then
      echo "  → $branch"
    else
      echo "    $branch"
    fi
  done <<< "$branches"
  echo

  # Show health status
  echo "Status:"
  local health_output
  health_output=$(check_stack_health "$stack_name" 2>&1)
  if [ $? -eq 0 ]; then
    echo "  ✅ Stack is healthy"
  else
    echo "  ⚠️  Stack needs attention:"
    echo "$health_output" | sed 's/^/    /'
  fi
}

# Fix a stack by rebasing divergent branches
# Usage: fix_stack [base_name]
# If no base_name is provided, uses the current branch's stack
function fix_stack() {
  local base_name="$1"
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  # If no base name provided, try to get it from current branch
  if [ -z "$base_name" ]; then
    if ! get_stack_info; then
      echo "Error: Not currently on a stack branch and no stack name provided."
      echo "Usage: $0 fix [stack-name]"
      exit 1
    fi
    base_name="$STACK_BASE"
  fi

  # Get all branches in the stack
  local branches
  branches=$(git branch --list "${base_name}-[0-9]*" --format="%(refname:short)" | sort -V)
  
  if [ -z "$branches" ]; then
    echo "Error: No branches found in stack '$base_name'"
    exit 1
  fi

  # Check if stack is healthy first
  if check_stack_health "$base_name" >/dev/null 2>&1; then
    echo "Stack '$base_name' is already healthy!"
    return 0
  fi

  # Find the divergent branch
  local prev_branch=""
  local divergent_branch=""
  local target_branch=""
  
  # First check if the first branch needs rebasing onto main
  first_branch=$(echo "$branches" | head -n1)
  if ! git merge-base --is-ancestor main "$first_branch" 2>/dev/null; then
    divergent_branch="$first_branch"
    target_branch="main"
  else
    # Check subsequent branches
    prev_branch="$first_branch"
    while read -r branch; do
      if ! git merge-base --is-ancestor "$prev_branch" "$branch" 2>/dev/null; then
        divergent_branch="$branch"
        target_branch="$prev_branch"
        break
      fi
      prev_branch="$branch"
    done <<< "$(echo "$branches" | tail -n +2)"
  fi

  if [ -z "$divergent_branch" ]; then
    echo "Error: Could not identify the divergent branch"
    exit 1
  fi

  echo "Found divergent branch: $divergent_branch"
  echo "Needs to be rebased onto: $target_branch"

  # Check for potential conflicts
  if ! git merge-base --is-ancestor "$target_branch" "$divergent_branch" 2>/dev/null; then
    # Try a dry-run rebase to check for conflicts
    if git rebase --no-ff --dry-run "$target_branch" "$divergent_branch" &>/dev/null; then
      echo "No conflicts detected, performing automatic rebase..."
      
      # Save current branch to return to it later
      local original_branch="$current_branch"
      
      # Checkout the divergent branch
      if ! git checkout "$divergent_branch"; then
        echo "Error: Failed to checkout $divergent_branch"
        exit 1
      fi
      
      # Perform the rebase
      if git rebase "$target_branch" --update-refs; then
        echo "Successfully rebased $divergent_branch onto $target_branch"
        
        # Return to original branch if different
        if [ "$original_branch" != "$divergent_branch" ]; then
          git checkout "$original_branch"
        fi
        
        # Check if the stack is now healthy
        if check_stack_health "$base_name" >/dev/null 2>&1; then
          echo "✅ Stack is now healthy!"
        else
          echo "⚠️  Stack may need additional fixes. Run 'git stack status' to check."
        fi
      else
        echo "Error: Rebase failed"
        echo "Aborting rebase..."
        git rebase --abort
        
        # Return to original branch
        if [ "$original_branch" != "$divergent_branch" ]; then
          git checkout "$original_branch"
        fi
        exit 1
      fi
    else
      echo "Conflicts detected, attempting to skip conflicting commit..."
      
      # Save current branch
      local original_branch="$current_branch"
      
      # Checkout the divergent branch
      if ! git checkout "$divergent_branch"; then
        echo "Error: Failed to checkout $divergent_branch"
        exit 1
      fi
      
      # Start the rebase
      if git rebase "$target_branch" --update-refs; then
        echo "Successfully rebased $divergent_branch onto $target_branch"
      else
        # If rebase stops due to conflict, try to skip the commit
        if [ -d ".git/rebase-apply" ] || [ -d ".git/rebase-merge" ]; then
          echo "Attempting to skip conflicting commit..."
          if git rebase --skip; then
            echo "Successfully skipped conflicting commit and completed rebase"
          else
            echo "Failed to skip conflicting commit"
            git rebase --abort
            if [ "$original_branch" != "$divergent_branch" ]; then
              git checkout "$original_branch"
            fi
            exit 1
          fi
        else
          echo "Rebase failed in an unexpected way"
          git rebase --abort
          if [ "$original_branch" != "$divergent_branch" ]; then
            git checkout "$original_branch"
          fi
          exit 1
        fi
      fi
      
      # Return to original branch if different
      if [ "$original_branch" != "$divergent_branch" ]; then
        git checkout "$original_branch"
      fi
      
      # Check if the stack is now healthy
      if check_stack_health "$base_name" >/dev/null 2>&1; then
        echo "✅ Stack is now healthy!"
      else
        echo "⚠️  Stack may need additional fixes. Run 'git stack status' to check."
      fi
    fi
  else
    echo "Error: Unexpected state - branches appear to be in sync"
    exit 1
  fi
}

# Navigate to the previous branch in the stack
function prev_stack() {
  if ! get_stack_info; then
    echo "Error: Current branch is not part of a stack (should match '<base>-<number>' pattern)."
    exit 1
  fi

  # If we're at feature-0, there is no previous branch
  if [ "$STACK_NUM" -eq 0 ]; then
    echo "Already at the first branch in stack. No previous branch exists."
    exit 0
  fi

  local prev_num=$((STACK_NUM - 1))
  local prev_branch="${STACK_BASE}-${prev_num}"

  # Check if the previous branch exists
  if ! git rev-parse --verify "$prev_branch" &>/dev/null; then
    echo "Error: Previous branch '$prev_branch' does not exist."
    exit 1
  fi

  # Checkout the previous branch
  if ! git checkout "$prev_branch"; then
    echo "Error: Failed to checkout branch '$prev_branch'."
    exit 1
  fi

  echo "Successfully checked out previous branch '$prev_branch'."
}

# Navigate to the next branch in the stack
function next_stack() {
  if ! get_stack_info; then
    echo "Error: Current branch is not part of a stack (should match '<base>-<number>' pattern)."
    exit 1
  fi

  local next_num=$((STACK_NUM + 1))
  local next_branch="${STACK_BASE}-${next_num}"

  # Check if the next branch exists
  if ! git rev-parse --verify "$next_branch" &>/dev/null; then
    echo "No next branch '$next_branch' exists in the stack."
    exit 0
  fi

  # Checkout the next branch
  if ! git checkout "$next_branch"; then
    echo "Error: Failed to checkout branch '$next_branch'."
    exit 1
  fi

  echo "Successfully checked out next branch '$next_branch'."
}

# Force-push all branches in a stack to remote
# Usage: fp_stack [base_name]
# If no base_name is provided, uses the current branch's stack
function fp_stack() {
  local base_name="$1"
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  # If no base name provided, try to get it from current branch
  if [ -z "$base_name" ]; then
    if ! get_stack_info; then
      echo "Error: Not currently on a stack branch and no stack name provided."
      echo "Usage: $0 fp [stack-name]"
      exit 1
    fi
    base_name="$STACK_BASE"
  fi

  # Get all branches in the stack
  local branches
  branches=$(git branch --list "${base_name}-[0-9]*" --format="%(refname:short)" | sort -V)
  
  if [ -z "$branches" ]; then
    echo "Error: No branches found in stack '$base_name'"
    exit 1
  fi

  # Save current branch to return to it later
  local original_branch="$current_branch"
  local success=true

  echo "Force-pushing branches in stack '$base_name' to remote..."
  while read -r branch; do
    echo "Pushing $branch..."
    if ! git push -f origin "$branch"; then
      echo "Error: Failed to push branch '$branch'"
      success=false
      break
    fi
  done <<< "$branches"

  # Return to original branch if different
  if [ "$original_branch" != "$current_branch" ]; then
    git checkout "$original_branch"
  fi

  if [ "$success" = true ]; then
    echo "✅ Successfully force-pushed all branches in stack '$base_name'"
  else
    echo "⚠️  Some branches may not have been pushed successfully"
    exit 1
  fi
}

# Create GitHub PR targeting correct parent branch in stack
# Usage: create_github_pr [additional-gh-args...]
function create_github_pr() {
  # Handle help flags
  for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
      echo "git stack pr - Create GitHub PR targeting correct parent branch"
      echo
      echo "Usage: git stack pr [gh-args...]"
      echo
      echo "This command automatically:"
      echo "  • Detects your current stack position (e.g., feature-2)"
      echo "  • Calculates the correct parent branch (feature-1, or main if feature-0)"
      echo "  • Creates PR targeting that parent branch"
      echo "  • Uses --fill to auto-populate title and description from commits"
      echo
      echo "Examples:"
      echo "  git stack pr                    # Basic PR creation"
      echo "  git stack pr --draft            # Create draft PR"
      echo "  git stack pr --reviewer @user   # Add reviewer"
      echo
      echo "Additional arguments are passed to 'gh pr create'."
      exit 0
    fi
  done

  # Check if gh CLI is available
  if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed or not in PATH."
    echo "Install it from: https://cli.github.com/"
    exit 1
  fi

  # Check if we're on a stack branch
  if ! get_stack_info; then
    echo "Error: Current branch is not part of a stack (should match '<base>-<number>' pattern)."
    echo "Cannot determine parent branch for PR creation."
    exit 1
  fi

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  local parent_branch

  # Determine parent branch
  if [ "$STACK_NUM" -eq 0 ]; then
    # For feature-0, target main or master
    if git rev-parse --verify main &>/dev/null; then
      parent_branch="main"
    elif git rev-parse --verify master &>/dev/null; then
      parent_branch="master"
    else
      echo "Error: Cannot find main or master branch to target."
      exit 1
    fi
  else
    # For feature-N (N > 0), target feature-(N-1)
    local parent_num=$((STACK_NUM - 1))
    parent_branch="${STACK_BASE}-${parent_num}"
    
    # Verify parent branch exists
    if ! git rev-parse --verify "$parent_branch" &>/dev/null; then
      echo "Error: Parent branch '$parent_branch' does not exist."
      echo "Stack may be incomplete or corrupted."
      exit 1
    fi
  fi

  # Show confirmation
  echo "Creating GitHub PR:"
  echo "  From: $current_branch"
  echo "  To:   $parent_branch"
  echo

  # Confirm with user
  read -r -p "Proceed with PR creation? [Y/n] " response
  response=${response:-y}  # Default to yes
  
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "PR creation cancelled."
    exit 0
  fi

  # Create PR with gh CLI
  echo "Running: gh pr create -B $parent_branch --fill $*"
  if gh pr create -B "$parent_branch" --fill "$@"; then
    echo "✅ GitHub PR created successfully!"
  else
    echo "❌ Failed to create GitHub PR"
    exit 1
  fi
}

# Only process arguments if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  subcommand="$1"
  shift

  # Subcommand dispatch
  case "$subcommand" in
    create)
      create_branch "$@"
      ;;
    increment)
      increment_stack
      ;;
    delete)
      if [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
        delete_stack "$1" "$2"
      else
        delete_shorthand
      fi
      ;;
    list)
      list_stacks
      ;;
    status)
      show_stack_status "$@"
      ;;
    fix)
      fix_stack "$@"
      ;;
    prev)
      prev_stack
      ;;
    next)
      next_stack
      ;;
    push)
      fp_stack "$@"
      ;;
    pr)
      create_github_pr "$@"
      ;;
    *)
      usage
      ;;
  esac
fi
