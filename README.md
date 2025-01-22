As a developer I want to check the changes done between git hash X and Y

Commit messages:

COMMIT_FROM=$0
COMMIT_TO=$1

COMMAND="git --no-pager log --oneline $COMMIT_FROM...$COMMIT_TO"

