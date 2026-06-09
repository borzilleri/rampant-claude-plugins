#!/usr/bin/env bash
# PreToolUse hook: warn when editing files on main/master.
# Advisory only -- always exits 0.

BRANCH=$(git branch --show-current 2>/dev/null) || exit 0

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "Warning: editing files on '$BRANCH'. Consider using a feature branch." >&2
fi

exit 0