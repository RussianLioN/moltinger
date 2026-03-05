#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/sync-claude-skills-to-codex.sh --install  # copy skills into $CODEX_HOME/skills
  ./scripts/sync-claude-skills-to-codex.sh --check    # verify destination is in sync
EOF
}

has_yaml_frontmatter() {
  local file="$1"
  local first_line

  # SKILL.md must begin with frontmatter and include a closing delimiter.
  first_line="$(head -n 1 "${file}" | tr -d '\r')"
  if [[ "${first_line}" != "---" ]]; then
    return 1
  fi

  awk '
    {
      sub(/\r$/, "", $0)
    }
    NR > 1 && $0 == "---" { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "${file}"
}

mode="${1:---install}"
if [[ "${mode}" != "--install" && "${mode}" != "--check" ]]; then
  usage
  exit 2
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required but not found in PATH" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

src_root="${repo_root}/.claude/skills"
dest_root="${CODEX_HOME:-$HOME/.codex}/skills"

if [[ ! -d "${src_root}" ]]; then
  echo "Source skills directory not found: ${src_root}" >&2
  exit 1
fi

declare -a invalid_frontmatter=()
while IFS= read -r -d '' skill_file; do
  skill_rel="${skill_file#${src_root}/}"
  if ! has_yaml_frontmatter "${skill_file}"; then
    invalid_frontmatter+=("${skill_rel}")
  fi
done < <(find "${src_root}" -type f -name "SKILL.md" -print0 | sort -z)

if [[ "${#invalid_frontmatter[@]}" -gt 0 ]]; then
  echo "Detected ${#invalid_frontmatter[@]} invalid SKILL.md file(s) without YAML frontmatter:" >&2
  printf ' - %s\n' "${invalid_frontmatter[@]}" >&2
  echo "Each SKILL.md must start with YAML frontmatter delimited by ---" >&2
  exit 1
fi

mkdir -p "${dest_root}"

synced=0
checked=0
declare -a missing_or_outdated=()

while IFS= read -r -d '' skill_file; do
  skill_dir="$(dirname "${skill_file}")"
  skill_rel="${skill_dir#${src_root}/}"
  dest_dir="${dest_root}/${skill_rel}"

  if [[ "${mode}" == "--check" ]]; then
    checked=$((checked + 1))
    if [[ ! -d "${dest_dir}" ]]; then
      missing_or_outdated+=("${skill_rel} (missing)")
      continue
    fi

    if rsync -an --delete "${skill_dir}/" "${dest_dir}/" | grep -q .; then
      missing_or_outdated+=("${skill_rel} (outdated)")
    fi
    continue
  fi

  mkdir -p "${dest_dir}"
  rsync -a --delete "${skill_dir}/" "${dest_dir}/"
  synced=$((synced + 1))
done < <(find "${src_root}" -type f -name "SKILL.md" -print0 | sort -z)

if [[ "${mode}" == "--check" ]]; then
  if [[ "${#missing_or_outdated[@]}" -eq 0 ]]; then
    echo "All ${checked} Claude skills are synced to ${dest_root}"
    exit 0
  fi

  echo "Detected ${#missing_or_outdated[@]} skill(s) missing or outdated in ${dest_root}:" >&2
  printf ' - %s\n' "${missing_or_outdated[@]}" >&2
  echo "Run: ./scripts/sync-claude-skills-to-codex.sh --install" >&2
  exit 1
fi

echo "Synced ${synced} Claude skills into ${dest_root}"
echo "Restart Codex to refresh skill discovery."
