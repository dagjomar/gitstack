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
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "Sourcing from: $SCRIPT_DIR/gitstack.sh"
  source "$SCRIPT_DIR/gitstack.sh"
}

# Test get_stack_info functionality
function test_get_stack_info() {
  echo "Testing get_stack_info..."
  
  # Create and checkout a test branch
  git checkout -b test-123 2>/dev/null
  echo "Created test-123 branch"
  
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
  git checkout -b not-a-stack-branch 2>/dev/null
  echo "Created not-a-stack-branch"
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
  git checkout -b bar-1 2>/dev/null
  git checkout -b bar-2 2>/dev/null
  git checkout -b bar-3 2>/dev/null
  git checkout -b other-1 2>/dev/null
  echo "Created test branches"
  
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

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

echo "Starting git stack tests..."

# Source gitstack.sh to get access to internal functions
source "$SCRIPT_DIR/gitstack.sh"

# Run new tests first
test_get_stack_info
test_get_stack_branches

# Optional: Clean up any existing test branches from previous runs
git branch -D foo-0 foo-1 foo-2 2>/dev/null || true

# 1. Create stack with base name 'foo'
"$SCRIPT_DIR/gitstack.sh" create foo
if [ "$(current_branch)" != "foo-0" ]; then
  fail "Expected current branch to be 'foo-0' after create, got '$(current_branch)'"
fi
echo "✅ Successfully created and checked out 'foo-0'"

# 2. Increment -> foo-1
"$SCRIPT_DIR/gitstack.sh" increment
if [ "$(current_branch)" != "foo-1" ]; then
  fail "Expected current branch to be 'foo-1' after increment, got '$(current_branch)'"
fi
echo "✅ Successfully incremented to 'foo-1'"

# 3. Increment -> foo-2
"$SCRIPT_DIR/gitstack.sh" increment
if [ "$(current_branch)" != "foo-2" ]; then
  fail "Expected current branch to be 'foo-2' after increment, got '$(current_branch)'"
fi
echo "✅ Successfully incremented to 'foo-2'"

echo "Deleting stack with '$SCRIPT_DIR/gitstack.sh delete -f foo'"
"$SCRIPT_DIR/gitstack.sh" delete -f foo

# Verify no foo-* branches remain
if git rev-parse --verify foo-0 &>/dev/null || \
   git rev-parse --verify foo-1 &>/dev/null || \
   git rev-parse --verify foo-2 &>/dev/null; then
  fail "Expected no foo-* branches to exist after delete -f foo"
fi
echo "✅ Successfully deleted all foo-* branches"

echo
echo "🎉 All tests passed!"

# Clean up
echo "Cleaning up test repository..."
cd - > /dev/null || exit 1
rm -rf "$TEST_DIR"
