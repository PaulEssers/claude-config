#!/usr/bin/env bash
# PreToolUse hook for Bash: deny any command that references a .env or .token
# file (.env, .env.prod, .token.casedb, ...). Template files such as
# .env.example stay allowed. A guardrail against accidental reads, not a
# security boundary: globs like .e* are not caught.
cmd=$(jq -r '.tool_input.command // empty')
stripped=$(printf '%s' "$cmd" | sed -E 's/\.env\.(example|sample|template|dist)//g')
if printf '%s' "$stripped" | grep -Eq '(^|[^[:alnum:]_])\.(env|token)([^[:alnum:]_]|$)'; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Blocked by ~/claude-config/hooks/block-secret-files.sh: the command references a .env or .token file, which hold real secrets and are off limits. Ask the user to run it or to paste the non-secret lines."}}'
fi
exit 0
