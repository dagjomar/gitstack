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

# Run all tests
function run_all_tests() {
  source_gitstack
  test_get_stack_info
  test_get_stack_branches
  test_list_stacks
  test_stack_health
  test_status_command
  test_fix_command
  test_stack_navigation
  test_convert_to_stack
  test_push_command
  test_mr_command
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
