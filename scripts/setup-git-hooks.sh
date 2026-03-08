#!/usr/bin/env bash
# Setup tracked Git hooks for session management and topology validation.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')"
HOOKS_DIR="$PROJECT_ROOT/.githooks"
REQUIRED_HOOKS=(
  pre-commit
  pre-push
  post-checkout
  post-merge
  post-rewrite
)

echo "Setting up tracked git hooks..."

for hook_name in "${REQUIRED_HOOKS[@]}"; do
  hook_path="${HOOKS_DIR}/${hook_name}"
  if [[ ! -f "${hook_path}" ]]; then
    echo "Missing tracked hook: ${hook_path}" >&2
    exit 1
  fi
  chmod +x "${hook_path}"
done

git config core.hooksPath .githooks

echo "Configured tracked hooks:"
for hook_name in "${REQUIRED_HOOKS[@]}"; do
  echo "  - ${hook_name}"
done
echo "Hooks location: ${HOOKS_DIR}"
echo "Git core.hooksPath: $(git config core.hooksPath)"
