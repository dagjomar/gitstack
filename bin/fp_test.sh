#!/bin/bash
#
# fp_test.sh - Test the force-push functionality of gitstack
#
# This script tests the fp command by using a real remote repository

set -e  # Exit immediately if a command exits with a nonzero status

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function fail() {
  echo "❌ Test failed: $1"
  exit 1
}

function verify_branch_exists() {
  local branch="$1"
  local message="$2"
  
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "✅ $message"
  else
    echo "❌ $message"
    echo "  Branch '$branch' not found"
    exit 1
  fi
}

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
echo "Creating test repository in $TEST_DIR"

# Create the remote (bare) repository
REMOTE_DIR="$TEST_DIR/remote"
mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR" || exit 1
git init --bare
echo "Created bare repository in $REMOTE_DIR"

# Create the local repository
LOCAL_DIR="$TEST_DIR/local"
mkdir -p "$LOCAL_DIR"
cd "$LOCAL_DIR" || exit 1
git init
git config --local user.email "test@example.com"
git config --local user.name "Test User"

# Add remote
git remote add origin "$REMOTE_DIR"

# Create initial commit
touch README.md
git add README.md
git commit -m "Initial commit"

echo "Starting fp command tests..."

# Create test stack
"$SCRIPT_DIR/gitstack.sh" create test-fp
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

echo "Testing fp with explicit stack name..."
"$SCRIPT_DIR/gitstack.sh" fp test-fp

# Clone the remote to verify the pushes
VERIFY_DIR="$TEST_DIR/verify"
git clone "$REMOTE_DIR" "$VERIFY_DIR"
cd "$VERIFY_DIR" || exit 1

# Verify all branches were pushed
verify_branch_exists "origin/test-fp-0" "fp should push first branch"
verify_branch_exists "origin/test-fp-1" "fp should push second branch"
verify_branch_exists "origin/test-fp-2" "fp should push third branch"

# Return to local repo
cd "$LOCAL_DIR" || exit 1

echo "Testing fp without stack name (using current branch)..."
git checkout test-fp-1

# Make a change to test force-push
echo "modified" > test2.txt
git commit -a --amend -m "test2 modified"

"$SCRIPT_DIR/gitstack.sh" fp

# Verify in the verify repo
cd "$VERIFY_DIR" || exit 1
git fetch origin

# Get the commit message of test-fp-1
commit_msg=$(git log -1 --format=%s origin/test-fp-1)
if [ "$commit_msg" = "test2 modified" ]; then
  echo "✅ fp successfully force-pushed amended commit"
else
  fail "fp did not force-push amended commit"
fi

# Return to local repo
cd "$LOCAL_DIR" || exit 1

echo "Testing error case - non-existent stack..."
if "$SCRIPT_DIR/gitstack.sh" fp nonexistent-stack 2>/dev/null; then
  fail "fp should fail on non-existent stack"
else
  echo "✅ fp correctly failed on non-existent stack"
fi

echo "Testing error case - not on stack branch and no stack provided..."
git checkout main
if "$SCRIPT_DIR/gitstack.sh" fp 2>/dev/null; then
  fail "fp should fail when not on stack branch and no stack provided"
else
  echo "✅ fp correctly failed when not on stack branch and no stack provided"
fi

# Clean up
git checkout main
"$SCRIPT_DIR/gitstack.sh" delete -f test-fp
rm -rf test1.txt test2.txt test3.txt

echo
echo "🎉 All fp tests passed!"

# Clean up test repository
cd - > /dev/null || exit 1
rm -rf "$TEST_DIR" 
