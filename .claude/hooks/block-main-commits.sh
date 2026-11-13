#!/bin/bash
# PreToolUse hook: block `git commit` / `git push` while on main, and pushes targeting main.
# Exit code 2 blocks the tool call and shows stderr to Claude.

input=$(cat)
command=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -z "$command" ] && exit 0

# Only care about git commit / git push invocations.
if ! grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(commit|push)([[:space:]]|$)' <<<"$command"; then
  exit 0
fi

# Check the branch where the command runs (worktree-aware), not the project root.
dir=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-.}"

# Honor `git -C <dir>` when present.
c_dir=$(grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' <<<"$command" | head -n 1 | awk '{print $3}' | tr -d "\"'")
if [ -n "$c_dir" ]; then
  case "$c_dir" in
    /*) dir="$c_dir" ;;
    *)  dir="$dir/$c_dir" ;;
  esac
fi

cd "$dir" 2>/dev/null || cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null
branch=$(git branch --show-current 2>/dev/null)

if [ "$branch" = "main" ]; then
  echo "Blocked: you are on 'main', which is protected. Create a branch first (git switch -c <type>/<topic>), then commit, push, and open a PR." >&2
  exit 2
fi

# Inspect only the `git push ...` segments themselves (not heredoc bodies such as commit messages).
push_args=$(grep -oE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push[^;&|]*' <<<"$command")
if grep -Eq '[[:space:]:+](refs/heads/)?main([[:space:]]|$)' <<<"$push_args"; then
  echo "Blocked: pushing to 'main' is not allowed. Push your feature branch and open a PR instead." >&2
  exit 2
fi

exit 0