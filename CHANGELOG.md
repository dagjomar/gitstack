# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **New `push` command** - Force-push all branches in a stack to remote with a single command
  - Usage: `git stack push [base_name]`
  - If no base name is provided, uses the current branch's stack
  - Pushes all branches in the stack sequentially
  - Returns to the original branch after pushing
  - Added comprehensive test coverage for the new command

### Changed
- Updated documentation to include the new push command
- Marked `git stack push` as completed in TODO.txt

### Technical Details
- The implementation leverages the existing `fp_stack` function
- Added to the command dispatch in the main script
- Integrated with existing error handling and branch validation