#!/bin/bash
#
# gitstack_test.sh - Basic integration test for Git Stack Management
#
# Prerequisites:
# - Must be inside a valid git repository.
# - 'git stack' command must be available (aliased or in PATH).
#
# Usage:
#   ./gitstack_test.sh
#
# Description:
#   1. Creates a stack with base name 'foo' -> foo-0
#   2. Checks that the current branch is foo-0
#   3. Increments -> foo-1
#   4. Checks current branch
#   5. Increments -> foo-2
#   6. Checks current branch
#   7. (Optional) Cleans up test branches

set -e  # Exit immediately if a command exits with a nonzero status

# Get the absolute path of the script directory BEFORE changing directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function current_branch() {
  git rev-parse --abbrev-ref HEAD
}

function fail() {
  echo "❌ Test failed: $1"
  exit 1
}

# Test helper function to source gitstack.sh and make functions available for testing
function source_gitstack() {
  # Source the main script to get access to internal functions
  echo "Sourcing from: $SCRIPT_DIR/gitstack.sh"
  source "$SCRIPT_DIR/gitstack.sh"
}

# Test get_stack_info functionality
function test_get_stack_info() {
  echo "Testing get_stack_info..."
  
  # Create and checkout a test branch
  if ! git checkout -b test-123; then
    echo "Failed to create test-123 branch. Trying to checkout existing branch..."
    if ! git checkout test-123; then
      fail "Could not create or checkout test-123 branch"
    fi
  fi
  echo "Created/checked out test-123 branch"
  
  if get_stack_info; then
    echo "Stack info: BASE=$STACK_BASE NUM=$STACK_NUM"
    if [ "$STACK_BASE" = "test" ] && [ "$STACK_NUM" = "123" ]; then
      echo "✅ get_stack_info correctly parsed base='test' and num='123'"
    else
      fail "get_stack_info parsed incorrect values: base='$STACK_BASE', num='$STACK_NUM'"
    fi
  else
    fail "get_stack_info failed to parse test-123"
  fi
  
  # Test with non-stack branch
  if ! git checkout -b not-a-stack-branch; then
    echo "Failed to create not-a-stack-branch. Trying to checkout existing branch..."
    if ! git checkout not-a-stack-branch; then
      fail "Could not create or checkout not-a-stack-branch"
    fi
  fi
  echo "Created/checked out not-a-stack-branch"
  
  if get_stack_info; then
    fail "get_stack_info incorrectly identified not-a-stack-branch as a stack branch"
  else
    echo "✅ get_stack_info correctly rejected non-stack branch"
  fi
  
  # Cleanup test branches
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  git branch -D test-123 not-a-stack-branch 2>/dev/null || true
}

# Test get_stack_branches functionality
function test_get_stack_branches() {
  echo "Testing get_stack_branches..."
  
  # Create test branches
  for branch in bar-1 bar-2 bar-3 other-1; do
    if ! git checkout -b "$branch"; then
      echo "Failed to create $branch. Trying to checkout existing branch..."
      if ! git checkout "$branch"; then
        fail "Could not create or checkout $branch"
      fi
    fi
  done
  echo "Created/checked out test branches"
  
  # Get branches and check count
  local branches
  branches=$(get_stack_branches "bar")
  echo "Found branches: $branches"
  local count
  count=$(echo "$branches" | grep -v '^$' | wc -l | tr -d ' ')
  echo "Branch count: $count"
  
  if [ "$count" -eq 3 ]; then
    echo "✅ get_stack_branches found correct number of branches"
  else
    fail "get_stack_branches found $count branches, expected 3"
  fi
  
  # Check specific branches
  if echo "$branches" | grep -q "bar-1" && \
     echo "$branches" | grep -q "bar-2" && \
     echo "$branches" | grep -q "bar-3"; then
    echo "✅ get_stack_branches found all expected branches"
  else
    fail "get_stack_branches missing some expected branches"
  fi
  
  # Cleanup test branches
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  git branch -D bar-1 bar-2 bar-3 other-1 2>/dev/null || true
}

# Test list_stacks functionality
function test_list_stacks() {
  echo "Testing list_stacks..."
  
  # Create some test stacks
  for branch in feature-0 feature-1 bugfix-0 bugfix-1 other-branch; do
    if ! git checkout -b "$branch"; then
      echo "Failed to create $branch. Trying to checkout existing branch..."
      if ! git checkout "$branch"; then
        fail "Could not create or checkout $branch"
      fi
    fi
  done
  echo "Created/checked out test branches"
  
  # Get all stack bases
  local stack_bases
  stack_bases=$(git branch --format='%(refname:short)' | grep -E '^.+-[0-9]+$' | sed -E 's/-[0-9]+$//' | sort -u)
  
  # Check that we found both stacks
  if echo "$stack_bases" | grep -q "feature" && \
     echo "$stack_bases" | grep -q "bugfix"; then
    echo "✅ list_stacks found all stack bases"
  else
    fail "list_stacks missing some stack bases"
  fi
  
  # Check that non-stack branch is not included
  if echo "$stack_bases" | grep -q "other-branch"; then
    fail "list_stacks incorrectly included non-stack branch"
  else
    echo "✅ list_stacks correctly excluded non-stack branch"
  fi
  
  # Cleanup test branches
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  git branch -D feature-0 feature-1 bugfix-0 bugfix-1 other-branch 2>/dev/null || true
}

# Test stack health check functionality
function test_stack_health() {
  echo "Testing stack health check..."

  # Create a healthy stack first
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create test-stack
  echo "test1" > test1.txt
  git add test1.txt
  git commit -m "test1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test2" > test2.txt
  git add test2.txt
  git commit -m "test2"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test3" > test3.txt
  git add test3.txt
  git commit -m "test3"

  # Test healthy stack
  local status
  status=$(get_stack_health_status "test-stack")
  assert_equals "healthy" "$status" "Stack should be healthy initially"

  # Make stack unhealthy by modifying the same file and amending
  git checkout test-stack-1
  git reset --hard main
  
  # Test unhealthy stack
  status=$(get_stack_health_status "test-stack")
  assert_equals "needs rebase" "$status" "Stack should need rebase after breaking chain"

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f test-stack
  rm -f test1.txt test2.txt test3.txt
}

# Add new assertion helper
function assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  
  if echo "$haystack" | grep -q "$needle"; then
    echo "❌ $message"
    echo "  Expected NOT to find: '$needle'"
    echo "  In:                  '$haystack'"
    exit 1
  else
    echo "✅ $message"
  fi
}

# Test status command functionality
function test_status_command() {
  echo "Testing status command..."

  # Create multiple stacks first
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create test-status-a
  echo "test1" > test1.txt
  git add test1.txt
  git commit -m "test1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test2" > test2.txt
  git add test2.txt
  git commit -m "test2"

  # Create another stack
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create test-status-b
  echo "test3" > test3.txt
  git add test3.txt
  git commit -m "test3"

  # Test status with no arguments (all stacks)
  local status_output
  status_output=$("$SCRIPT_DIR/gitstack.sh" status)
  assert_contains "$status_output" "Stack: test-status-a" "Status should show first stack"
  assert_contains "$status_output" "Stack: test-status-b" "Status should show second stack"
  assert_contains "$status_output" "test-status-a-0" "Status should list first stack's branches"
  assert_contains "$status_output" "test-status-b-0" "Status should list second stack's branches"

  # Test status with explicit stack name
  status_output=$("$SCRIPT_DIR/gitstack.sh" status test-status-a)
  assert_contains "$status_output" "Stack: test-status-a" "Status with arg should show stack name"
  assert_not_contains "$status_output" "Stack: test-status-b" "Status with arg should not show other stacks"

  # Make first stack unhealthy
  git checkout test-status-a-1
  git reset --hard main
  
  # Test status shows unhealthy state for specific stack
  status_output=$("$SCRIPT_DIR/gitstack.sh" status test-status-a)
  assert_contains "$status_output" "needs rebase" "Status should show unhealthy stack"

  # Test status shows both healthy and unhealthy stacks
  status_output=$("$SCRIPT_DIR/gitstack.sh" status)
  assert_contains "$status_output" "needs rebase" "Status should show unhealthy stack"
  assert_contains "$status_output" "Stack is healthy" "Status should show healthy stack"

  # Clean up
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  "$SCRIPT_DIR/gitstack.sh" delete -f test-status-a
  "$SCRIPT_DIR/gitstack.sh" delete -f test-status-b
  rm -f test1.txt test2.txt test3.txt
  echo "✅ Status command tests passed"
}

# Test helper functions
function assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  
  if [ "$expected" = "$actual" ]; then
    echo "✅ $message"
  else
    echo "❌ $message"
    echo "  Expected: '$expected'"
    echo "  Got:      '$actual'"
    exit 1
  fi
}

function assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  
  if echo "$haystack" | grep -q "$needle"; then
    echo "✅ $message"
  else
    echo "❌ $message"
    echo "  Expected to find: '$needle'"
    echo "  In:              '$haystack'"
    exit 1
  fi
}

# Test fix command functionality
function test_fix_command() {
  echo "Testing fix command..."

  # Create a healthy stack first
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create test-fix
  echo "test1" > test1.txt
  git add test1.txt
  git commit -m "test1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test2" > test2.txt
  git add test2.txt
  git commit -m "test2"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test3" > test3.txt
  git add test3.txt
  git commit -m "test3"

  # Test healthy stack
  local status
  status=$(get_stack_health_status "test-fix")
  assert_equals "healthy" "$status" "Stack should be healthy initially"

  # Make stack unhealthy by resetting middle branch to main
  git checkout test-fix-1
  git reset --hard main
  
  # Test unhealthy stack
  status=$(get_stack_health_status "test-fix")
  assert_equals "needs rebase" "$status" "Stack should need rebase after breaking chain"

  # Try to fix the stack
  if ! "$SCRIPT_DIR/gitstack.sh" fix test-fix; then
    fail "Fix command failed"
  fi

  # Verify stack is healthy again
  status=$(get_stack_health_status "test-fix")
  assert_equals "healthy" "$status" "Stack should be healthy after fix"

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f test-fix
  rm -f test1.txt test2.txt test3.txt
  echo "✅ Fix command tests passed"
}

# Test prev and next navigation functionality
function test_stack_navigation() {
  echo "Testing stack navigation (prev/next)..."

  # Create a test stack with multiple branches
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  "$SCRIPT_DIR/gitstack.sh" create nav-test
  echo "test1" > test1.txt
  git add test1.txt
  git commit -m "test1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test2" > test2.txt
  git add test2.txt
  git commit -m "test2"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test3" > test3.txt
  git add test3.txt
  git commit -m "test3"

  # Test navigation from middle branch
  git checkout nav-test-1
  
  # Test next navigation
  "$SCRIPT_DIR/gitstack.sh" next
  local current
  current=$(current_branch)
  if [ "$current" = "nav-test-2" ]; then
    echo "✅ next command successfully navigated to nav-test-2"
  else
    fail "next command failed to navigate to nav-test-2, got $current"
  fi

  # Test prev navigation
  "$SCRIPT_DIR/gitstack.sh" prev
  current=$(current_branch)
  if [ "$current" = "nav-test-1" ]; then
    echo "✅ prev command successfully navigated to nav-test-1"
  else
    fail "prev command failed to navigate to nav-test-1, got $current"
  fi

  # Test prev at start of stack
  git checkout nav-test-0
  if "$SCRIPT_DIR/gitstack.sh" prev 2>&1 | grep -q "Already at the first branch"; then
    echo "✅ prev command correctly handled start of stack"
  else
    fail "prev command should indicate when at start of stack"
  fi

  # Test next at end of stack
  git checkout nav-test-2
  if "$SCRIPT_DIR/gitstack.sh" next 2>&1 | grep -q "No next branch"; then
    echo "✅ next command correctly handled end of stack"
  else
    fail "next command should indicate when at end of stack"
  fi

  # Test on non-stack branch
  git checkout -b not-a-stack-branch
  if "$SCRIPT_DIR/gitstack.sh" next 2>&1 | grep -q "not part of a stack"; then
    echo "✅ navigation commands correctly handle non-stack branches"
  else
    fail "navigation commands should error on non-stack branches"
  fi

  # Clean up
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  "$SCRIPT_DIR/gitstack.sh" delete -f nav-test
  git branch -D not-a-stack-branch
  rm -f test1.txt test2.txt test3.txt
}

# Test convert to stack functionality
function test_convert_to_stack() {
  echo "Testing convert to stack..."
  
  # Create a regular branch
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  git checkout -b dj/my-feature
  
  # Test converting to stack branch
  # Simulate user input 'y' for the prompt
  echo "y" | "$SCRIPT_DIR/gitstack.sh" create
  
  local current
  current=$(current_branch)
  if [ "$current" = "dj/my-feature-0" ]; then
    echo "✅ Successfully converted 'dj/my-feature' to 'dj/my-feature-0'"
  else
    fail "Failed to convert branch to stack, got '$current'"
  fi
  
  # Verify the original branch no longer exists
  if git rev-parse --verify dj/my-feature &>/dev/null; then
    fail "Original branch 'dj/my-feature' still exists after conversion"
  else
    echo "✅ Original branch 'dj/my-feature' was properly renamed"
  fi
  
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  git branch -D dj/my-feature-0
}

# Test push command functionality
function test_push_command() {
  echo "Testing push command..."

  # Set up a fake remote to test pushing
  git init --bare "$TEST_DIR/remote.git"
  git remote add origin "$TEST_DIR/remote.git"

  # Create a test stack with multiple branches
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  "$SCRIPT_DIR/gitstack.sh" create push-test
  echo "test1" > test1.txt
  git add test1.txt
  git commit -m "test1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test2" > test2.txt
  git add test2.txt
  git commit -m "test2"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test3" > test3.txt
  git add test3.txt
  git commit -m "test3"

  # Test push from current stack branch
  if "$SCRIPT_DIR/gitstack.sh" push 2>&1 | grep -q "Successfully force-pushed all branches"; then
    echo "✅ push command successfully pushed from current stack"
  else
    fail "push command failed to push from current stack"
  fi

  # Verify all branches were pushed to remote
  local remote_branches
  remote_branches=$(git ls-remote --heads origin | awk '{print $2}' | sed 's|refs/heads/||')
  
  if echo "$remote_branches" | grep -q "push-test-0" && \
     echo "$remote_branches" | grep -q "push-test-1" && \
     echo "$remote_branches" | grep -q "push-test-2"; then
    echo "✅ All stack branches successfully pushed to remote"
  else
    fail "Not all stack branches were pushed to remote"
  fi

  # Test push with explicit stack name from different branch
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  if "$SCRIPT_DIR/gitstack.sh" push push-test 2>&1 | grep -q "Successfully force-pushed all branches"; then
    echo "✅ push command with explicit stack name worked"
  else
    fail "push command with explicit stack name failed"
  fi

  # Clean up
  git remote remove origin
  rm -rf "$TEST_DIR/remote.git"
  "$SCRIPT_DIR/gitstack.sh" delete -f push-test
  rm -f test1.txt test2.txt test3.txt
}

# Test MR creation functionality
function test_mr_command() {
  echo "Testing MR command..."

  # Create a test stack
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  "$SCRIPT_DIR/gitstack.sh" create mr-test
  echo "test1" > test1.txt
  git add test1.txt
  git commit -m "test1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test2" > test2.txt
  git add test2.txt
  git commit -m "test2"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  echo "test3" > test3.txt
  git add test3.txt
  git commit -m "test3"

  # Create a temporary mock script
  local mock_script="/tmp/mock_glab_$$.sh"
  echo '#!/bin/bash
# Print all arguments for debugging
echo "[MOCK GLAB] args: $@" >&2
if [ "$1" = "mr" ] && [ "$2" = "create" ]; then
  from_branch=$(git rev-parse --abbrev-ref HEAD)
  to_branch=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-b" ]]; then
      shift
      to_branch="$1"
      break
    fi
    shift
  done
  echo "Mock: Creating MR from $from_branch to $to_branch"
  exit 0
fi
exit 1' > "$mock_script"
  chmod +x "$mock_script"

  # Temporarily modify PATH to use our mock
  local original_path="$PATH"
  export PATH="/tmp:$PATH"
  mv "$mock_script" "/tmp/glab"

  # Test MR creation from middle branch
  git checkout mr-test-1
  local output
  output=$(echo y | "$SCRIPT_DIR/gitstack.sh" mr 2>&1)
  echo "$output"
  if echo "$output" | grep -q "Mock: Creating MR from mr-test-1 to mr-test-0"; then
    echo "✅ MR command correctly targets previous branch"
  else
    fail "MR command failed to target correct branch"
  fi

  # Test MR creation from first branch
  git checkout mr-test-0
  output=$(echo y | "$SCRIPT_DIR/gitstack.sh" mr 2>&1)
  echo "$output"
  if echo "$output" | grep -q "Mock: Creating MR from mr-test-0 to main"; then
    echo "✅ MR command correctly targets main for first branch"
  else
    fail "MR command failed to target main for first branch"
  fi

  # Test with additional arguments
  output=$(echo y | "$SCRIPT_DIR/gitstack.sh" mr --draft --reviewer @user 2>&1)
  echo "$output"
  if echo "$output" | grep -q "Mock: Creating MR from mr-test-0 to main"; then
    echo "✅ MR command correctly passes additional arguments"
  else
    fail "MR command failed to pass additional arguments"
  fi

  # Test help flag (no prompt expected)
  output=$("$SCRIPT_DIR/gitstack.sh" mr --help 2>&1)
  echo "$output"
  if echo "$output" | grep -q "git stack mr - Create GitLab MR"; then
    echo "✅ MR command shows help text"
  else
    fail "MR command failed to show help text"
  fi

  # Test error when not on stack branch (no prompt expected)
  git checkout -b not-a-stack-branch
  output=$("$SCRIPT_DIR/gitstack.sh" mr 2>&1 || true)
  echo "$output"
  if echo "$output" | grep -q "Error: Current branch is not part of a stack"; then
    echo "✅ MR command correctly errors on non-stack branch"
  else
    fail "MR command failed to error on non-stack branch"
  fi

  # Clean up
  git checkout main 2>/dev/null || git checkout master 2>/dev/null
  "$SCRIPT_DIR/gitstack.sh" delete -f mr-test
  git branch -D not-a-stack-branch 2>/dev/null || true
  rm -f test1.txt test2.txt test3.txt
  rm -f "/tmp/glab"
  export PATH="$original_path"
}

# Test for stack fix bug with merge conflict and downstream changes
function test_stack_fix_merge_conflict_bug() {
  echo "Testing stack fix bug with merge conflict and downstream changes..."

  # Setup: create stack and files
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create conflict-stack-branch
  echo "original line a 1" > a.txt
  git add a.txt
  echo "original line b 1" > b.txt
  echo "original line b 2" >> b.txt
  git add b.txt
  git commit -m "edit a.txt and b.txt in conflict-stack-branch-0"

  # increment stack
  "$SCRIPT_DIR/gitstack.sh" increment

  # Create edits to a new file b.txt, modifying line 2
  echo "original line b 1" > b.txt
  echo "edited line b 2" >> b.txt
  echo "new line b 3" >> b.txt
  git add b.txt
  git commit -m "edit b.txt (line 2,3) in conflict-stack-branch-1"

  # go back to previous commit in stack
  "$SCRIPT_DIR/gitstack.sh" prev

  # Create conflicting edits to b.txt (line 1)
  echo "upstream edited line b 1" > b.txt
  echo "upstream edited line b 2" >> b.txt
  
  git add b.txt
  git commit -m "edit a.txt and b.txt in conflict-stack-branch-0"

  # This will now break the stack, and our tree at branch-1 will contain the old commit from branch-0
  
  # Run fix and expect failure due to merge conflict
  output=$("$SCRIPT_DIR/gitstack.sh" fix conflict-stack-branch 2>&1 || true)
  if echo "$output" | grep -q "Conflicts detected during rebase" && echo "$output" | grep -q "Found divergent branch: conflict-stack-branch-1" && echo "$output" | grep -q "Needs to be rebased onto: conflict-stack-branch-0" && echo "$output" | grep -q "Please manually resolve the conflicts by rebasing 'conflict-stack-branch-1' onto 'conflict-stack-branch-0'"; then
    echo "✅ Fix command failed as expected with clear merge conflict error message (non-tip case)"
  else
    echo "$output"
    fail "Fix command did not fail as expected or did not print the correct error message (non-tip case)"
  fi

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f conflict-stack-branch
  rm -f a.txt b.txt
}

# Test rebase command functionality (experimental rebase --onto algorithm)
function test_rebase_command() {
  echo "Testing rebase command (experimental rebase --onto algorithm)..."

  # Using 1 commit per branch (as required by the rebase command)
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create rebase-test
  
  # Branch 0: 1 commit with file a1.txt
  echo "content a1" > a1.txt
  git add a1.txt
  git commit -m "commit on rebase-test-0"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  
  # Branch 1: 1 commit with file b1.txt (different file, no conflict)
  echo "content b1" > b1.txt
  git add b1.txt
  git commit -m "commit on rebase-test-1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  
  # Branch 2: 1 commit with file c1.txt (different file, no conflict)
  echo "content c1" > c1.txt
  git add c1.txt
  git commit -m "commit on rebase-test-2"

  # Verify initial state is healthy
  local status
  status=$(get_stack_health_status "rebase-test")
  assert_equals "healthy" "$status" "Stack should be healthy initially"

  # Make stack unhealthy by amending a commit in branch-0
  # Only modify a1.txt (the file that belongs to this branch)
  git checkout rebase-test-0
  echo "content a1 amended" > a1.txt
  git add a1.txt
  git commit --amend --no-edit
  
  # Verify stack is now unhealthy
  status=$(get_stack_health_status "rebase-test")
  assert_equals "needs rebase" "$status" "Stack should need rebase after amending"

  # Test rebase command (should succeed without conflicts since each branch uses different files)
  if ! "$SCRIPT_DIR/gitstack.sh" rebase rebase-test; then
    fail "Rebase command failed"
  fi

  # Verify stack is healthy again
  status=$(get_stack_health_status "rebase-test")
  assert_equals "healthy" "$status" "Stack should be healthy after rebase"

  # Verify that commits are preserved
  git checkout rebase-test-1
  if [ ! -f "b1.txt" ]; then
    fail "File from rebase-test-1 should exist after rebase"
  fi
  if ! grep -q "content b1" b1.txt; then
    fail "File contents should be preserved on rebase-test-1"
  fi
  
  git checkout rebase-test-2
  if [ ! -f "c1.txt" ]; then
    fail "File from rebase-test-2 should exist after rebase"
  fi
  if ! grep -q "content c1" c1.txt; then
    fail "File contents should be preserved on rebase-test-2"
  fi

  # Verify the amended commit is in rebase-test-0
  git checkout rebase-test-0
  if ! grep -q "content a1 amended" a1.txt; then
    fail "Amended commit should be preserved in rebase-test-0"
  fi

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f rebase-test
  rm -f a1.txt b1.txt c1.txt
  echo "✅ Rebase command tests passed"
}

# Test rebase command with single file line conflict
function test_rebase_single_file_line_conflict() {
  echo "Testing rebase command with single file line conflict..."

  # Create a stack with two branches, both modifying the same line in the same file
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create conflict-test
  
  # Branch 0: modify line 1 of file.txt
  echo "line 1 from branch-0" > file.txt
  echo "line 2" >> file.txt
  git add file.txt
  git commit -m "modify line 1 on conflict-test-0"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  
  # Branch 1: modify the same line 1 of file.txt (will conflict)
  echo "line 1 from branch-1" > file.txt
  echo "line 2" >> file.txt
  git add file.txt
  git commit -m "modify line 1 on conflict-test-1"

  # Verify initial state is healthy
  local status
  status=$(get_stack_health_status "conflict-test")
  assert_equals "healthy" "$status" "Stack should be healthy initially"

  # Make stack unhealthy by amending branch-0 (modifying the same line again)
  git checkout conflict-test-0
  echo "line 1 from branch-0 amended" > file.txt
  echo "line 2" >> file.txt
  git add file.txt
  git commit --amend --no-edit
  
  # Verify stack is now unhealthy
  status=$(get_stack_health_status "conflict-test")
  assert_equals "needs rebase" "$status" "Stack should need rebase after amending"

  # Test rebase command - should detect conflict and abort, or succeed if git can resolve it
  output=$("$SCRIPT_DIR/gitstack.sh" rebase conflict-test 2>&1 || true)
  
  # Check if rebase succeeded (git might be able to resolve the conflict automatically)
  if echo "$output" | grep -q "Successfully rebased all branches"; then
    # Rebase succeeded - verify stack is healthy
    status=$(get_stack_health_status "conflict-test")
    if [ "$status" = "healthy" ]; then
      echo "✅ Rebase succeeded (git was able to resolve the conflict automatically)"
    else
      fail "Rebase reported success but stack is not healthy"
    fi
  elif echo "$output" | grep -q "Rebase procedure aborted due to merge conflicts"; then
    # Conflict detected and rebase aborted
    echo "✅ Conflict correctly detected and rebase aborted"
    
    # Verify that we got instructions for manual resolution
    if echo "$output" | grep -q "Please manually rebase"; then
      echo "✅ Manual resolution instructions provided"
    else
      fail "Expected manual resolution instructions, but they weren't provided"
    fi
    
    # Verify repository is in a clean state (no rebase in progress)
    if [ -d ".git/rebase-apply" ] || [ -d ".git/rebase-merge" ]; then
      fail "Repository should be in clean state (no rebase in progress), but rebase directories exist"
    else
      echo "✅ Repository is in clean state after abort"
    fi
  else
    # Unexpected outcome
    fail "Rebase did not succeed or abort as expected. Output: $output"
  fi

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f conflict-test
  rm -f file.txt
  echo "✅ Rebase single file line conflict test passed"
}

# Test rebase command with single file, different lines (conflict expected)
# Note: Even when branches modify different lines, rebasing can still cause conflicts
# because git needs to reapply the changes on top of the amended base commit
function test_rebase_single_file_different_lines_conflict() {
  echo "Testing rebase command with single file, different lines (conflict expected)..."

  # Create a stack with two branches, modifying different lines in the same file
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create no-conflict-test
  
  # Branch 0: modify line 1 of file.txt
  echo "line 1 from branch-0" > file.txt
  echo "line 2" >> file.txt
  git add file.txt
  git commit -m "modify line 1 on no-conflict-test-0"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  
  # Branch 1: add a new line (line 3) without modifying line 1
  # Even though different lines are modified, this can still conflict during rebase
  echo "line 1 from branch-0" > file.txt
  echo "line 2" >> file.txt
  echo "line 3 from branch-1" >> file.txt
  git add file.txt
  git commit -m "add line 3 on no-conflict-test-1"

  # Verify initial state is healthy
  local status
  status=$(get_stack_health_status "no-conflict-test")
  assert_equals "healthy" "$status" "Stack should be healthy initially"

  # Make stack unhealthy by amending branch-0 (modifying line 1 again)
  git checkout no-conflict-test-0
  echo "line 1 from branch-0 amended" > file.txt
  echo "line 2" >> file.txt
  git add file.txt
  git commit --amend --no-edit
  
  # Verify stack is now unhealthy
  status=$(get_stack_health_status "no-conflict-test")
  assert_equals "needs rebase" "$status" "Stack should need rebase after amending"

  # Test rebase command - may succeed or conflict depending on git's ability to reapply changes
  # Git needs to reapply branch-1's changes on top of the amended base
  output=$("$SCRIPT_DIR/gitstack.sh" rebase no-conflict-test 2>&1 || true)
  
  # Check if rebase succeeded (git might be able to resolve it automatically)
  if echo "$output" | grep -q "Successfully rebased all branches"; then
    # Rebase succeeded - verify stack is healthy
    status=$(get_stack_health_status "no-conflict-test")
    if [ "$status" = "healthy" ]; then
      echo "✅ Rebase succeeded (git was able to resolve changes automatically)"
    else
      fail "Rebase reported success but stack is not healthy"
    fi
  elif echo "$output" | grep -q "Rebase procedure aborted due to merge conflicts"; then
    # Conflict detected and rebase aborted
    echo "✅ Conflict correctly detected (even different lines can conflict during rebase)"
    
    # Verify repository is in a clean state
    if [ -d ".git/rebase-apply" ] || [ -d ".git/rebase-merge" ]; then
      fail "Repository should be in clean state (no rebase in progress), but rebase directories exist"
    else
      echo "✅ Repository is in clean state after abort"
    fi
  else
    # Unexpected outcome
    fail "Rebase did not succeed or abort as expected. Output: $output"
  fi

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f no-conflict-test
  rm -f file.txt
  echo "✅ Rebase single file different lines conflict test passed"
}

# Test rebase command with non-overlapping line ranges (no conflict expected)
# Branch 0 edits lines 1-5, Branch 1 edits lines 1-2, Branch 2 edits lines 4-5
# When amending branch 1 (lines 1-2), branch 2 (lines 4-5) should rebase without conflict
# Using branch~N syntax allows git to rebase cleanly when line ranges don't overlap
function test_rebase_non_overlapping_lines_no_conflict() {
  echo "Testing rebase command with non-overlapping line ranges (no conflict expected)..."

  # Create a stack with three branches editing different line ranges
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" create non-overlap-test
  
  # Branch 0: create file with lines 1-5
  echo "line 1 from branch-0" > file.txt
  echo "line 2 from branch-0" >> file.txt
  echo "line 3" >> file.txt
  echo "line 4 from branch-0" >> file.txt
  echo "line 5 from branch-0" >> file.txt
  git add file.txt
  git commit -m "create file with lines 1-5 on non-overlap-test-0"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  
  # Branch 1: edit lines 1-2 only
  echo "line 1 from branch-1" > file.txt
  echo "line 2 from branch-1" >> file.txt
  echo "line 3" >> file.txt
  echo "line 4 from branch-0" >> file.txt
  echo "line 5 from branch-0" >> file.txt
  git add file.txt
  git commit -m "edit lines 1-2 on non-overlap-test-1"
  
  "$SCRIPT_DIR/gitstack.sh" increment
  
  # Branch 2: edit lines 4-5 only (non-overlapping with branch-1's lines 1-2)
  echo "line 1 from branch-1" > file.txt
  echo "line 2 from branch-1" >> file.txt
  echo "line 3" >> file.txt
  echo "line 4 from branch-2" >> file.txt
  echo "line 5 from branch-2" >> file.txt
  git add file.txt
  git commit -m "edit lines 4-5 on non-overlap-test-2"

  # Verify initial state is healthy
  local status
  status=$(get_stack_health_status "non-overlap-test")
  assert_equals "healthy" "$status" "Stack should be healthy initially"

  # Make stack unhealthy by amending branch-1 (modifying lines 1-2 again)
  git checkout non-overlap-test-1
  echo "line 1 from branch-1 amended" > file.txt
  echo "line 2 from branch-1 amended" >> file.txt
  echo "line 3" >> file.txt
  echo "line 4 from branch-0" >> file.txt
  echo "line 5 from branch-0" >> file.txt
  git add file.txt
  git commit --amend --no-edit
  
  # Verify stack is now unhealthy
  status=$(get_stack_health_status "non-overlap-test")
  assert_equals "needs rebase" "$status" "Stack should need rebase after amending"

  # Test rebase command - should succeed without conflicts when using branch~N syntax
  # This works because git can cleanly apply non-overlapping changes
  if ! "$SCRIPT_DIR/gitstack.sh" rebase non-overlap-test; then
    fail "Rebase command should succeed without conflicts when line ranges don't overlap"
  fi

  # Verify stack is healthy again
  status=$(get_stack_health_status "non-overlap-test")
  assert_equals "healthy" "$status" "Stack should be healthy after rebase"

  # Verify that all changes are preserved correctly
  git checkout non-overlap-test-1
  if ! grep -q "line 1 from branch-1 amended" file.txt; then
    fail "Amended line 1 should be preserved in non-overlap-test-1"
  fi
  if ! grep -q "line 2 from branch-1 amended" file.txt; then
    fail "Amended line 2 should be preserved in non-overlap-test-1"
  fi
  
  git checkout non-overlap-test-2
  # Branch 2 should have the amended lines 1-2 from branch-1, plus its own lines 4-5
  if ! grep -q "line 1 from branch-1 amended" file.txt; then
    fail "Amended line 1 from branch-1 should be present in non-overlap-test-2 after rebase"
  fi
  if ! grep -q "line 2 from branch-1 amended" file.txt; then
    fail "Amended line 2 from branch-1 should be present in non-overlap-test-2 after rebase"
  fi
  if ! grep -q "line 4 from branch-2" file.txt; then
    fail "Line 4 from branch-2 should be preserved after rebase"
  fi
  if ! grep -q "line 5 from branch-2" file.txt; then
    fail "Line 5 from branch-2 should be preserved after rebase"
  fi
  
  # Verify the file has all expected lines
  local line_count
  line_count=$(wc -l < file.txt | tr -d ' ')
  if [ "$line_count" -ne 5 ]; then
    fail "File should have 5 lines after rebase, but has $line_count"
  fi

  # Clean up
  git checkout main
  "$SCRIPT_DIR/gitstack.sh" delete -f non-overlap-test
  rm -f file.txt
  echo "✅ Rebase non-overlapping lines no conflict test passed"
}

# Test rebase command error handling
function test_rebase_command_errors() {
  echo "Testing rebase command error handling..."

  # Test error when not on a stack branch and no stack name provided
  git checkout main
  git checkout -b not-a-stack-branch
  output=$("$SCRIPT_DIR/gitstack.sh" rebase 2>&1 || true)
  if echo "$output" | grep -q "Error: Not currently on a stack branch"; then
    echo "✅ Rebase command correctly errors on non-stack branch"
  else
    fail "Rebase command should error on non-stack branch"
  fi

  # Test error when stack doesn't exist
  output=$("$SCRIPT_DIR/gitstack.sh" rebase nonexistent-stack 2>&1 || true)
  if echo "$output" | grep -q "Error: No branches found in stack"; then
    echo "✅ Rebase command correctly errors on nonexistent stack"
  else
    fail "Rebase command should error on nonexistent stack"
  fi

  # Clean up
  git checkout main
  git branch -D not-a-stack-branch 2>/dev/null || true
  echo "✅ Rebase command error handling tests passed"
}

# Test rebase prev command
function test_rebase_prev_command() {
  echo "Testing rebase prev command..."

  # Create a stack with 2 branches
  "$SCRIPT_DIR/gitstack.sh" create rebase-prev-test
  echo "file0" > file0.txt
  git add file0.txt
  git commit -m "commit on rebase-prev-test-0"

  "$SCRIPT_DIR/gitstack.sh" increment
  echo "file1" > file1.txt
  git add file1.txt
  git commit -m "commit on rebase-prev-test-1"

  # Break the stack by amending the first branch
  git checkout rebase-prev-test-0
  echo "amended" >> file0.txt
  git add file0.txt
  git commit --amend -m "amended on rebase-prev-test-0"

  # Verify stack is unhealthy
  status=$(get_stack_health_status "rebase-prev-test")
  assert_equals "needs rebase" "$status" "Stack should need rebase after amending"

  # Test rebase prev command on branch 1
  git checkout rebase-prev-test-1
  if ! "$SCRIPT_DIR/gitstack.sh" rebase prev; then
    fail "Rebase prev command should succeed"
  fi

  # Verify stack is now healthy
  status=$(get_stack_health_status "rebase-prev-test")
  assert_equals "healthy" "$status" "Stack should be healthy after rebase prev"

  # Verify the amended commit is in the chain
  git checkout rebase-prev-test-1
  if ! git log --oneline | grep -q "amended"; then
    fail "Amended commit should be in rebase-prev-test-1 after rebase"
  fi
  # Verify the contents of file0
  if ! grep -q "amended" file0.txt; then
    fail "File0 should contain 'amended' after rebase"
  fi

  # Test error when on branch-0 (no previous branch)
  git checkout rebase-prev-test-0
  output=$("$SCRIPT_DIR/gitstack.sh" rebase prev 2>&1 || true)
  if echo "$output" | grep -q "Error: Already at the first branch in stack"; then
    echo "✅ Rebase prev correctly errors on branch-0"
  else
    fail "Rebase prev should error on branch-0"
  fi

  # Test error when not on a stack branch
  git checkout main
  git checkout -b not-a-stack
  output=$("$SCRIPT_DIR/gitstack.sh" rebase prev 2>&1 || true)
  if echo "$output" | grep -q "Error: Current branch is not part of a stack"; then
    echo "✅ Rebase prev correctly errors on non-stack branch"
  else
    fail "Rebase prev should error on non-stack branch"
  fi

  # Clean up
  git checkout main
  git branch -D not-a-stack 2>/dev/null || true
  "$SCRIPT_DIR/gitstack.sh" delete -f rebase-prev-test
  echo "✅ Rebase prev command tests passed"
}

# Run all tests
function run_all_tests() {
  source_gitstack
  test_get_stack_info
  test_get_stack_branches
  test_list_stacks
  test_stack_health
  test_status_command
  test_fix_command
  test_stack_fix_merge_conflict_bug
  test_stack_navigation
  test_convert_to_stack
  test_push_command
  test_mr_command
  test_rebase_command
  test_rebase_single_file_line_conflict
  test_rebase_single_file_different_lines_conflict
  test_rebase_non_overlapping_lines_no_conflict
  test_rebase_command_errors
  test_rebase_prev_command
}

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
echo "Creating test repository in $TEST_DIR"
cd "$TEST_DIR" || exit 1

# Initialize test repository
git init
git config --local user.email "test@example.com"
git config --local user.name "Test User"

# Create initial commit
touch README.md
git add README.md
git commit -m "Initial commit"

# Rename master to main if needed (for consistency)
if git rev-parse --verify master &>/dev/null && ! git rev-parse --verify main &>/dev/null; then
  git branch -m master main
fi

echo "Starting git stack tests..."

# Run all tests
run_all_tests

echo
echo "🎉 All tests passed!"

# Clean up
echo "Cleaning up test repository..."
cd - > /dev/null || true
rm -rf "$TEST_DIR"
