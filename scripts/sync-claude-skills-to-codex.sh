#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/sync-claude-skills-to-codex.sh --install  # sync Claude skills + bridge commands/agents into $CODEX_HOME/skills
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

slugify() {
  local input="$1"

  # Normalize path-like ids into stable directory names.
  input="${input%.md}"
  input="${input//\//--}"
  input="$(printf '%s' "${input}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/[.]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"

  if [[ -z "${input}" ]]; then
    input="artifact"
  fi

  printf '%s' "${input}"
}

extract_description() {
  local file="$1"
  local description

  description="$(awk '
    {
      sub(/\r$/, "", $0)
    }
    NR == 1 {
      if ($0 == "---") {
        in_frontmatter = 1
        next
      } else {
        exit
      }
    }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "${file}")"

  printf '%s' "${description}"
}

yaml_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

append_bundled_source() {
  local source_rel="$1"
  local source_file="$2"
  local output_file="$3"

  cat >> "${output_file}" <<EOF

## Bundled Source Artifact

Origin path: \`${source_rel}\`

The original Claude artifact content is embedded below so this installed skill remains self-contained after sync into \`\$CODEX_HOME/skills\`.

<!-- BEGIN BUNDLED SOURCE -->
EOF

  cat "${source_file}" >> "${output_file}"
  printf '\n<!-- END BUNDLED SOURCE -->\n' >> "${output_file}"
}

write_bridge_skill() {
  local artifact_type="$1"
  local source_rel="$2"
  local source_file="$3"
  local output_file="$4"
  local title
  local description
  local escaped_description

  if [[ "${artifact_type}" == "command" ]]; then
    title="Claude Command Bridge"
  else
    title="Claude Agent Bridge"
  fi

  description="$(extract_description "${source_file}")"
  if [[ -z "${description}" ]]; then
    description="Migrated Claude ${artifact_type} from ${source_rel}"
  fi
  escaped_description="$(yaml_escape "${description}")"

  cat > "${output_file}" <<EOF
---
description: "${escaped_description}"
origin: "${source_rel}"
---

# ${title}

This skill is auto-generated from the Claude ${artifact_type} artifact originally stored at \`${source_rel}\`.

## Instructions

1. Read the bundled source artifact in the `## Bundled Source Artifact` section below.
2. Execute the workflow intent and output format defined in that bundled source.
3. Translate Claude-specific tool names to the closest Codex equivalents when needed.
4. If a native Codex skill conflicts with this bridge, prefer the native skill and keep behavioral parity.
EOF

  append_bundled_source "${source_rel}" "${source_file}" "${output_file}"
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
commands_root="${repo_root}/.claude/commands"
agents_root="${repo_root}/.claude/agents"
dest_root="${CODEX_HOME:-$HOME/.codex}/skills"

if [[ ! -d "${src_root}" ]]; then
  echo "Source skills directory not found: ${src_root}" >&2
  exit 1
fi
if [[ ! -d "${commands_root}" ]]; then
  echo "Source commands directory not found: ${commands_root}" >&2
  exit 1
fi
if [[ ! -d "${agents_root}" ]]; then
  echo "Source agents directory not found: ${agents_root}" >&2
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

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

generated_root="${tmp_root}/generated"
generated_commands_root="${generated_root}/claude-bridge/commands"
generated_agents_root="${generated_root}/claude-bridge/agents"
mkdir -p "${generated_commands_root}" "${generated_agents_root}"

command_bridges=0
while IFS= read -r -d '' command_file; do
  command_rel="${command_file#${commands_root}/}"
  command_slug="$(slugify "${command_rel}")"
  command_skill_dir="${generated_commands_root}/command-${command_slug}"
  mkdir -p "${command_skill_dir}"
  write_bridge_skill "command" ".claude/commands/${command_rel}" "${command_file}" "${command_skill_dir}/SKILL.md"
  command_bridges=$((command_bridges + 1))
done < <(find "${commands_root}" -type f -name "*.md" -print0 | sort -z)

agent_bridges=0
while IFS= read -r -d '' agent_file; do
  agent_rel="${agent_file#${agents_root}/}"
  agent_slug="$(slugify "${agent_rel}")"
  agent_skill_dir="${generated_agents_root}/agent-${agent_slug}"
  mkdir -p "${agent_skill_dir}"
  write_bridge_skill "agent" ".claude/agents/${agent_rel}" "${agent_file}" "${agent_skill_dir}/SKILL.md"
  agent_bridges=$((agent_bridges + 1))
done < <(find "${agents_root}" -type f -name "*.md" -print0 | sort -z)

mkdir -p "${dest_root}"

native_synced=0
checked=0
declare -a missing_or_outdated=()
declare -a bridge_missing_or_outdated=()

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
  native_synced=$((native_synced + 1))
done < <(find "${src_root}" -type f -name "SKILL.md" -print0 | sort -z)

bridge_commands_dest="${dest_root}/claude-bridge/commands"
bridge_agents_dest="${dest_root}/claude-bridge/agents"

if [[ "${mode}" == "--check" ]]; then
  if [[ ! -d "${bridge_commands_dest}" ]]; then
    bridge_missing_or_outdated+=("claude-bridge/commands (missing)")
  elif rsync -an --delete "${generated_commands_root}/" "${bridge_commands_dest}/" | grep -q .; then
    bridge_missing_or_outdated+=("claude-bridge/commands (outdated)")
  fi

  if [[ ! -d "${bridge_agents_dest}" ]]; then
    bridge_missing_or_outdated+=("claude-bridge/agents (missing)")
  elif rsync -an --delete "${generated_agents_root}/" "${bridge_agents_dest}/" | grep -q .; then
    bridge_missing_or_outdated+=("claude-bridge/agents (outdated)")
  fi

  if [[ "${#missing_or_outdated[@]}" -eq 0 && "${#bridge_missing_or_outdated[@]}" -eq 0 ]]; then
    echo "All ${checked} Claude skills, ${command_bridges} command bridges, and ${agent_bridges} agent bridges are synced to ${dest_root}"
    exit 0
  fi

  if [[ "${#missing_or_outdated[@]}" -gt 0 ]]; then
    echo "Detected ${#missing_or_outdated[@]} Claude skill(s) missing or outdated in ${dest_root}:" >&2
    printf ' - %s\n' "${missing_or_outdated[@]}" >&2
  fi
  if [[ "${#bridge_missing_or_outdated[@]}" -gt 0 ]]; then
    echo "Detected ${#bridge_missing_or_outdated[@]} bridge bundle(s) missing or outdated in ${dest_root}:" >&2
    printf ' - %s\n' "${bridge_missing_or_outdated[@]}" >&2
  fi
  echo "Run: ./scripts/sync-claude-skills-to-codex.sh --install" >&2
  exit 1
fi

mkdir -p "${bridge_commands_dest}" "${bridge_agents_dest}"
rsync -a --delete "${generated_commands_root}/" "${bridge_commands_dest}/"
rsync -a --delete "${generated_agents_root}/" "${bridge_agents_dest}/"

echo "Synced ${native_synced} Claude skills into ${dest_root}"
echo "Synced ${command_bridges} command bridges and ${agent_bridges} agent bridges into ${dest_root}/claude-bridge"
echo "Restart Codex to refresh skill discovery."
