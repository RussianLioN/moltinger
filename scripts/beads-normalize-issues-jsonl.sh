#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-normalize-issues-jsonl.sh [--path <issues.jsonl>]
  scripts/beads-normalize-issues-jsonl.sh --check [--path <issues.jsonl>]

Normalize tracked .beads/issues.jsonl dependency ordering without changing
issue semantics. The canonical order is:
1. dependency created_at (ascending)
2. dependency type priority (parent-child before blocks, then others)
3. dependency type/name tiebreakers
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

issues_path=".beads/issues.jsonl"
check_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      [[ $# -ge 2 ]] || die "--path requires a value"
      issues_path="$2"
      shift 2
      ;;
    --check)
      check_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

mode_probe_root="$(dirname "$issues_path")"
if repo_root="$(git -C "${mode_probe_root}" rev-parse --show-toplevel 2>/dev/null)"; then
  if [[ -f "${repo_root}/.beads/cutover-mode.json" ]]; then
    printf '%s\n' "Cutover mode retires tracked .beads/issues.jsonl normalization; use ./scripts/beads-dolt-rollout.sh verify --worktree . instead." >&2
    exit 24
  fi
  if [[ -f "${repo_root}/.beads/pilot-mode.json" ]]; then
    printf '%s\n' "Pilot mode retires tracked .beads/issues.jsonl normalization; use ./scripts/beads-dolt-pilot.sh review instead." >&2
    exit 24
  fi
fi

[[ -f "$issues_path" ]] || die "Beads issues file not found: $issues_path"
command -v python3 >/dev/null 2>&1 || die "python3 is required to normalize $issues_path"

tmp_file="$(mktemp "${TMPDIR:-/tmp}/beads-issues-normalize.XXXXXX")"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

python3 - "$issues_path" "$tmp_file" <<'PY'
import json
import sys

source_path, target_path = sys.argv[1:3]
type_rank = {"parent-child": 0, "blocks": 1}


def dependency_key(dependency):
    return (
        dependency.get("created_at", ""),
        type_rank.get(dependency.get("type", ""), 2),
        dependency.get("type", ""),
        dependency.get("depends_on_id", ""),
        dependency.get("issue_id", ""),
        dependency.get("created_by", ""),
    )


def find_dependencies_slice(line):
    field = '"dependencies":'
    field_index = line.find(field)
    if field_index == -1:
        return None

    array_start = line.find("[", field_index + len(field))
    if array_start == -1:
        raise ValueError("dependencies field is missing its array opener")

    in_string = False
    escaped = False
    depth = 0

    for index in range(array_start, len(line)):
        char = line[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return array_start, index + 1

    raise ValueError("dependencies array is not terminated")


with open(source_path, "r", encoding="utf-8", newline="") as handle:
    input_lines = handle.readlines()

output_lines = []

for raw_line in input_lines:
    line = raw_line[:-1] if raw_line.endswith("\n") else raw_line
    if not line.strip():
        output_lines.append(raw_line)
        continue

    document = json.loads(line)
    dependencies = document.get("dependencies")
    if not isinstance(dependencies, list) or len(dependencies) < 2:
        output_lines.append(raw_line)
        continue

    normalized_dependencies = sorted(dependencies, key=dependency_key)
    if normalized_dependencies == dependencies:
        output_lines.append(raw_line)
        continue

    slice_bounds = find_dependencies_slice(line)
    if slice_bounds is None:
        output_lines.append(raw_line)
        continue

    dep_start, dep_end = slice_bounds
    dep_json = json.dumps(normalized_dependencies, ensure_ascii=False, separators=(",", ":"))
    normalized_line = line[:dep_start] + dep_json + line[dep_end:]
    output_lines.append(normalized_line + ("\n" if raw_line.endswith("\n") else ""))

with open(target_path, "w", encoding="utf-8", newline="") as handle:
    handle.writelines(output_lines)
PY

if cmp -s "$issues_path" "$tmp_file"; then
  exit 0
fi

if [[ "$check_only" -eq 1 ]]; then
  printf '%s\n' "Non-canonical dependency order in ${issues_path}" >&2
  exit 1
fi

mv "$tmp_file" "$issues_path"
trap - EXIT
printf '%s\n' "${issues_path}"
