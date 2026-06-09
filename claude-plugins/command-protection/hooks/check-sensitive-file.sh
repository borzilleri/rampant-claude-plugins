#!/usr/bin/env bash
# Block edits to sensitive files.
# Reads TOOL_INPUT JSON from stdin, extracts file_path, and checks
# against protected patterns. Exits 2 to block, 0 to allow.

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "Blocked: jq not installed (required for safety hook)" >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
BASENAME_LOWER=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')

# Secrets and credentials
if echo "$BASENAME_LOWER" | grep -qE '^\.(env|env\..*)$'; then
  echo "Blocked: cannot modify environment file ($BASENAME)" >&2
  exit 2
fi
if echo "$BASENAME_LOWER" | grep -qE '\.(pem|key|secret)$'; then
  echo "Blocked: cannot modify key/secret file ($BASENAME)" >&2
  exit 2
fi
if echo "$BASENAME_LOWER" | grep -qE '^credentials'; then
  echo "Blocked: cannot modify credentials file ($BASENAME)" >&2
  exit 2
fi

# SSH keys
if echo "$BASENAME_LOWER" | grep -qE '^id_(rsa|dsa|ecdsa|ed25519)'; then
  echo "Blocked: cannot modify SSH key ($BASENAME)" >&2
  exit 2
fi

# Auth config files
case "$BASENAME_LOWER" in
  .npmrc|.pypirc|.netrc|.htpasswd)
    echo "Blocked: cannot modify auth config file ($BASENAME)" >&2
    exit 2
    ;;
  kubeconfig|token.json|tokens.json)
    echo "Blocked: cannot modify credential file ($BASENAME)" >&2
    exit 2
    ;;
esac

# Docker credentials
if echo "$FILE_PATH" | grep -qE '\.docker/config\.json$'; then
  echo "Blocked: cannot modify Docker credentials ($FILE_PATH)" >&2
  exit 2
fi

# Lockfiles
case "$BASENAME" in
  package-lock.json|yarn.lock|pnpm-lock.yaml|go.sum|Cargo.lock|poetry.lock|composer.lock|Gemfile.lock)
    echo "Blocked: cannot modify lockfile ($BASENAME)" >&2
    exit 2
    ;;
esac

# Git internals
if echo "$FILE_PATH" | grep -qE '(^|/)\.git/'; then
  echo "Blocked: cannot modify git internals ($FILE_PATH)" >&2
  exit 2
fi

# CI/CD secrets
if echo "$FILE_PATH" | grep -qE '\.github/secrets'; then
  echo "Blocked: cannot modify CI/CD secrets ($FILE_PATH)" >&2
  exit 2
fi

exit 0