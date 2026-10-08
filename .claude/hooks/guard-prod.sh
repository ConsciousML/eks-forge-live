#!/usr/bin/env bash
# PreToolUse hook on Bash. Blocks apply and destroy on prod, asks on live/bootstrap.
# ponytail: string match on command and cwd, a wrapper script bypasses it. Upgrade path is a
# GitHub Environment with required reviewers on the CD job.

# Fails closed without jq.
command -v jq >/dev/null || { echo "guard-prod: jq not found" >&2; exit 2; }

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$input")
where="$(jq -r '.cwd // ""' <<<"$input") $command"

grep -qE '(terragrunt|tofu)[^|;&]*[[:space:]](apply|destroy)([[:space:]]|$)' <<<"$command" || exit 0

if grep -q 'live/bootstrap' <<<"$where"; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask",
    permissionDecisionReason: "Bootstrap resources are shared by staging and prod."}}'
elif grep -qE '(^|[/[:space:]])prod([/[:space:]]|$)' <<<"$where"; then
  echo "Blocked: apply and destroy on prod only run through CD. Give the user the command." >&2
  exit 2
fi
