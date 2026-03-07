#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/rca-completion-check.sh --check [--range <git-range>] [--hook <name>]

Description:
  Blocks incomplete RCA protocol pushes.
  If commits include RCA reports (docs/rca/YYYY-MM-DD-*.md), they must also include
  instruction updates (AGENTS.md, CLAUDE.md, or docs/rules/*.md).
EOF
}

action="check"
range_arg=""
hook_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      action="check"
      shift
      ;;
    --range)
      range_arg="${2:-}"
      if [[ -z "${range_arg}" ]]; then
        echo "[rca-completion-check] --range requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --hook)
      hook_name="${2:-}"
      if [[ -z "${hook_name}" ]]; then
        echo "[rca-completion-check] --hook requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[rca-completion-check] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${action}" != "check" ]]; then
  echo "[rca-completion-check] Unsupported action: ${action}" >&2
  exit 2
fi

if ! git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "[rca-completion-check] Not inside a git repository; skipping."
  exit 0
fi

cd "${git_root}"

range_to_check="${range_arg}"
if [[ -z "${range_to_check}" ]]; then
  if git rev-parse --verify --quiet '@{upstream}' >/dev/null; then
    range_to_check='@{upstream}..HEAD'
  else
    range_to_check='HEAD'
  fi
fi

collect_files() {
  local range="$1"
  if [[ "${range}" == *".."* ]]; then
    git diff --name-only "${range}"
  else
    git show --name-only --pretty='format:' "${range}"
  fi
}

changed_files="$(collect_files "${range_to_check}" | sed '/^$/d' | sort -u)"
if [[ -z "${changed_files}" ]]; then
  exit 0
fi

rca_files="$(printf '%s\n' "${changed_files}" | grep -E '^docs/rca/[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$' || true)"
if [[ -z "${rca_files}" ]]; then
  exit 0
fi

instruction_files="$(printf '%s\n' "${changed_files}" | grep -E '^(AGENTS\.md|CLAUDE\.md|docs/rules/.+\.md)$' || true)"
if [[ -n "${instruction_files}" ]]; then
  echo "[rca-completion-check] RCA protocol check passed for ${range_to_check}."
  exit 0
fi

if [[ -n "${hook_name}" ]]; then
  echo "[rca-completion-check] ${hook_name} blocked: incomplete RCA protocol." >&2
else
  echo "[rca-completion-check] Incomplete RCA protocol." >&2
fi
echo "[rca-completion-check] Range: ${range_to_check}" >&2
echo "[rca-completion-check] RCA files detected:" >&2
while IFS= read -r rca_file; do
  [[ -n "${rca_file}" ]] || continue
  echo "  - ${rca_file}" >&2
done <<< "${rca_files}"
echo "[rca-completion-check] Required additional changes: AGENTS.md, CLAUDE.md, or docs/rules/*.md" >&2
echo "[rca-completion-check] Add instruction updates, then retry push." >&2
exit 1
