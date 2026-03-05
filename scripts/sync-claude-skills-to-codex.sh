#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/sync-claude-skills-to-codex.sh --install  # copy skills into $CODEX_HOME/skills
  ./scripts/sync-claude-skills-to-codex.sh --check    # verify destination is in sync
EOF
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

mkdir -p "${dest_root}"

synced=0
checked=0
declare -a missing_or_outdated=()

while IFS= read -r -d '' skill_dir; do
  skill_name="$(basename "${skill_dir}")"
  if [[ ! -f "${skill_dir}/SKILL.md" ]]; then
    continue
  fi

  dest_dir="${dest_root}/${skill_name}"

  if [[ "${mode}" == "--check" ]]; then
    checked=$((checked + 1))
    if [[ ! -d "${dest_dir}" ]]; then
      missing_or_outdated+=("${skill_name} (missing)")
      continue
    fi

    if rsync -an --delete "${skill_dir}/" "${dest_dir}/" | grep -q .; then
      missing_or_outdated+=("${skill_name} (outdated)")
    fi
    continue
  fi

  mkdir -p "${dest_dir}"
  rsync -a --delete "${skill_dir}/" "${dest_dir}/"
  synced=$((synced + 1))
done < <(find "${src_root}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

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
