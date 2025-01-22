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

echo "Starting git stack tests..."

# Optional: Clean up any existing test branches from previous runs
git branch -D foo-0 foo-1 foo-2 2>/dev/null || true

# 1. Create stack with base name 'foo'
git stack create foo
if [ "$(current_branch)" != "foo-0" ]; then
  fail "Expected current branch to be 'foo-0' after create, got '$(current_branch)'"
fi
echo "✅ Successfully created and checked out 'foo-0'"

# 2. Increment -> foo-1
git stack increment
if [ "$(current_branch)" != "foo-1" ]; then
  fail "Expected current branch to be 'foo-1' after increment, got '$(current_branch)'"
fi
echo "✅ Successfully incremented to 'foo-1'"

# 3. Increment -> foo-2
git stack increment
if [ "$(current_branch)" != "foo-2" ]; then
  fail "Expected current branch to be 'foo-2' after increment, got '$(current_branch)'"
fi
echo "✅ Successfully incremented to 'foo-2'"

echo "Deleting stack with 'git stack delete -f foo'"
git stack delete -f foo

# Verify no foo-* branches remain
if git rev-parse --verify foo-0 &>/dev/null || \
   git rev-parse --verify foo-1 &>/dev/null || \
   git rev-parse --verify foo-2 &>/dev/null; then
  fail "Expected no foo-* branches to exist after delete -f foo"
fi
echo "✅ Successfully deleted all foo-* branches"

echo
echo "🎉 All tests passed!"

# Optional: Clean up test branches
# Uncomment if you want to remove these branches automatically:
# git checkout main || git checkout master || true
# git branch -D foo-0 foo-1 foo-2
