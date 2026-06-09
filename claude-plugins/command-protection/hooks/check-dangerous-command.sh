#!/usr/bin/env bash
# Block dangerous shell commands before execution.
# Reads TOOL_INPUT JSON from stdin, extracts the command, and checks
# against known destructive patterns. Exits 2 to block, 0 to allow.

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "Blocked: jq not installed (required for safety hook)" >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Strip content that isn't executable code before scanning:
#   1. Heredoc bodies (<<'EOF'...EOF, <<"EOF"...EOF, <<EOF...EOF)
#   2. Strings passed to commit/tag message flags (-m "...", -F file)
#   3. Double-quoted strings (may contain natural language)
#   4. Single-quoted strings
# This prevents commit messages, echo strings, and heredoc content
# from triggering false positives.
STRIPPED=$(echo "$COMMAND" | \
  sed -E '
    # Remove -m "..." and -m '"'"'...'"'"' (message flags with quoted args)
    s/-[mM][[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    # Remove -m"..." (no space variant)
    s/-[mM]("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    # Remove -F <file> (message from file -- the file content is not in the command,
    # but the flag+path is harmless noise to remove for consistency)
    s/-F[[:space:]]+[^[:space:]]+//g
    # Remove --body "..." and --body '"'"'...'"'"' (gh flag with quoted args)
    s/--body[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    # Remove --body="..." variant
    s/--body=("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    # Remove --message "..." variant
    s/--message[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    s/--message=("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    # Remove --title "..." variant
    s/--title[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"')//g
    s/--title=("[^"]*"|'"'"'[^'"'"']*'"'"')//g
  ')

# Strip heredoc bodies: everything between <<['"]?DELIM['"]? and DELIM
STRIPPED=$(echo "$STRIPPED" | perl -0pe 's/<<-?\s*[\x27"]?(\w+)[\x27"]?\s*\n.*?\n\s*\1\b//gs' 2>/dev/null || echo "$STRIPPED")

# Also strip $(cat <<'EOF'...EOF) pattern used by Claude for commit messages
STRIPPED=$(echo "$STRIPPED" | perl -0pe 's/\$\(cat\s+<<\s*[\x27"]?(\w+)[\x27"]?\s*\n.*?\n\s*\1\s*\)//gs' 2>/dev/null || echo "$STRIPPED")

CMD_LOWER=$(echo "$STRIPPED" | tr '[:upper:]' '[:lower:]')

# --- Destructive rm: blocklist of critical system paths ---
PROTECTED_PATHS="^(/|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/private|/private/etc|/private/var|/proc|/root|/run|/sbin|/srv|/sys|/usr|/usr/bin|/usr/include|/usr/lib|/usr/local|/usr/local/bin|/usr/local/sbin|/usr/local/share|/usr/sbin|/usr/share|/usr/src|/var|/System|/Library|/Applications|/Users|/Network|/Volumes)/?$"

if echo "$CMD_LOWER" | grep -qE '\brm\s+.*(-[a-z]*[rR]|--(recursive|remove))'; then
  for arg in $COMMAND; do
    [[ "$arg" == -* ]] && continue
    [[ "$arg" == "rm" ]] && continue
    normalized=$(echo "$arg" | sed 's:/\+:/:g; s:/$::')
    [[ -z "$normalized" || "$normalized" == "/" ]] && normalized="/"
    if echo "$normalized" | grep -qE "$PROTECTED_PATHS"; then
      echo "Blocked: rm -r targeting protected path ($normalized)" >&2
      exit 2
    fi
  done
  if echo "$CMD_LOWER" | grep -qE '\brm\s+.*(-[a-z]*[rR]).*(\s+/\*|\s+~/?(\*|$))'; then
    echo "Blocked: rm -r with dangerous glob (/* or ~/*)" >&2
    exit 2
  fi
fi

# SQL destructive operations (only when a SQL client is the command)
if echo "$CMD_LOWER" | grep -qE '\b(psql|pgcli|pg_dump|pg_restore|mysql|mycli|sqlite3|mariadb|sqlcmd|bq|clickhouse|clickhouse-client|mongosh|cqlsh|redis-cli)\b' && \
   echo "$CMD_LOWER" | grep -qE '(drop\s+table|drop\s+database|truncate\s+table|truncate\s+)'; then
  echo "Blocked: destructive SQL command detected (DROP/TRUNCATE)" >&2
  exit 2
fi

# Force push to protected branches (git and gh)
if echo "$CMD_LOWER" | grep -qE '(git|gh)\s+.*push\s+.*(--force|-f\b)' && echo "$CMD_LOWER" | grep -qE '\b(main|master)\b'; then
  echo "Blocked: force push to protected branch (main/master)" >&2
  exit 2
fi

# --- Visible-to-others actions: prompt for approval (exit 2 = block, JSON ask = prompt) ---

# gh commands that post visible comments/reviews
if echo "$CMD_LOWER" | grep -qE 'gh\s+(pr|issue)\s+(comment|review)'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will post a comment/review visible to others."}}'
  exit 0
fi

# External messaging
if echo "$CMD_LOWER" | grep -qE '\bunvrs\s+teams\s+send\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will send a Teams message."}}'
  exit 0
fi
if echo "$CMD_LOWER" | grep -qE '\bunvrs\s+outlook\s+send\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will send an email via Outlook."}}'
  exit 0
fi

# Package installs (supply chain risk)
if echo "$CMD_LOWER" | grep -qE '\b(npm|yarn|pnpm)\s+(install|add|i)\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will install npm packages."}}'
  exit 0
fi
if echo "$CMD_LOWER" | grep -qE '\bpip3?\s+install\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will install Python packages."}}'
  exit 0
fi
if echo "$CMD_LOWER" | grep -qE '\bbrew\s+install\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will install a Homebrew package."}}'
  exit 0
fi
if echo "$CMD_LOWER" | grep -qE '\bgo\s+install\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will install a Go binary."}}'
  exit 0
fi
if echo "$CMD_LOWER" | grep -qE '\bcargo\s+install\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will install a Rust crate."}}'
  exit 0
fi
if echo "$CMD_LOWER" | grep -qE '\bgem\s+install\b'; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This will install a Ruby gem."}}'
  exit 0
fi

# Destructive git operations
if echo "$CMD_LOWER" | grep -qE 'git\s+reset\s+--hard'; then
  echo "Blocked: git reset --hard (destroys uncommitted work)" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'git\s+branch\s+-D\s'; then
  echo "Blocked: git branch -D (force-deletes branch without merge check)" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'git\s+checkout\s+\.\s*$'; then
  echo "Blocked: git checkout . (discards all unstaged changes)" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'git\s+clean\s+-[a-z]*f'; then
  echo "Blocked: git clean -f (permanently deletes untracked files)" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'git\s+stash\s+(drop|clear)'; then
  echo "Blocked: git stash drop/clear (permanently loses stashed work)" >&2
  exit 2
fi

# System-level dangerous commands
if echo "$CMD_LOWER" | grep -qE 'chmod\s+777\s+/'; then
  echo "Blocked: chmod 777 on root path" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE '\bmkfs\b'; then
  echo "Blocked: mkfs (filesystem creation) command detected" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE '\bdd\s+if='; then
  echo "Blocked: dd command detected (disk-level operations)" >&2
  exit 2
fi

# Fork bomb
if echo "$COMMAND" | grep -qE ':\(\)\s*\{.*:\|:.*\}'; then
  echo "Blocked: fork bomb detected" >&2
  exit 2
fi

# Disk overwrite
if echo "$CMD_LOWER" | grep -qE '>\s*/dev/sd[a-z]'; then
  echo "Blocked: direct write to block device" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'dd\s+.*of=/dev/'; then
  echo "Blocked: dd output to block device" >&2
  exit 2
fi

# --- Infrastructure / cloud destructive operations ---

# Kubernetes
if echo "$CMD_LOWER" | grep -qE 'kubectl\s+delete\b'; then
  echo "Blocked: kubectl delete (destroys cluster resources)" >&2
  exit 2
fi

# Helm
if echo "$CMD_LOWER" | grep -qE 'helm\s+(uninstall|delete)\b'; then
  echo "Blocked: helm uninstall/delete (removes release)" >&2
  exit 2
fi

# Terraform
if echo "$CMD_LOWER" | grep -qE 'terraform\s+destroy\b'; then
  echo "Blocked: terraform destroy (tears down infrastructure)" >&2
  exit 2
fi

# AWS destructive operations
if echo "$CMD_LOWER" | grep -qE 'aws\s+s3\s+(rm|rb)\b.*--recursive'; then
  echo "Blocked: aws s3 rm/rb --recursive (bulk deletes S3 objects)" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'aws\s+ec2\s+terminate-instances'; then
  echo "Blocked: aws ec2 terminate-instances" >&2
  exit 2
fi
if echo "$CMD_LOWER" | grep -qE 'aws\s+(rds|dynamodb|cloudformation)\s+delete'; then
  echo "Blocked: aws destructive operation (delete on managed service)" >&2
  exit 2
fi

# Direct push to main/master (non-force) - advisory warning, not block
if echo "$CMD_LOWER" | grep -qE '(git|gh)\s+push\b' && echo "$CMD_LOWER" | grep -qE '\b(main|master)\b'; then
  if ! echo "$CMD_LOWER" | grep -qE '(--force|-f\b)'; then
    echo "Warning: pushing directly to main/master. Consider using a branch + PR." >&2
  fi
fi

exit 0