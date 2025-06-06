# Add `push` command to gitstack

## Summary

This PR adds a new `push` command to gitstack that allows users to force-push all branches in a stack to remote with a single command.

## Problem

Previously, users had to manually push each branch in their stack individually, which was tedious and error-prone, especially for stacks with many branches. The functionality (`fp_stack`) already existed in the codebase but wasn't exposed as a user-facing command.

## Solution

- Exposed the existing `fp_stack` function as the `push` command
- Added command to the help documentation and usage instructions
- Added comprehensive test coverage for the new command
- Updated README.md with push command documentation
- Marked the feature as completed in TODO.txt

## Usage

```bash
# Push all branches in the current stack
git stack push

# Push all branches in a specific stack
git stack push feature-xyz
```

## Testing

- Added new test function `test_push_command()` that verifies:
  - Pushing from current stack branch
  - Pushing with explicit stack name
  - All branches are successfully pushed to remote
- All existing tests continue to pass
- Manual testing confirms the command works as expected

## Benefits

- **Efficiency**: Push entire stacks with one command instead of pushing each branch individually
- **Safety**: Maintains current branch context (returns to original branch after pushing)
- **Consistency**: Uses the same patterns as other gitstack commands

This is a small, focused improvement that enhances the daily workflow of gitstack users.