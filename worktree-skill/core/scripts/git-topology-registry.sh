#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/git-topology-registry.sh refresh [--write-doc]
  scripts/git-topology-registry.sh check
  scripts/git-topology-registry.sh status
  scripts/git-topology-registry.sh doctor [--prune] [--write-doc]

Description:
  Owner script for the sanitized git topology registry and reviewed intent sidecar.
  Live git topology is the source of truth; the intent sidecar adds reviewed notes and lifecycle intent.
EOF
}

action=""
write_doc=false
prune=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    refresh|check|status|doctor)
      if [[ -n "${action}" ]]; then
        echo "[git-topology-registry] Multiple actions provided." >&2
        usage >&2
        exit 2
      fi
      action="$1"
      shift
      ;;
    --write-doc)
      write_doc=true
      shift
      ;;
    --prune)
      prune=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[git-topology-registry] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${action}" ]]; then
  usage >&2
  exit 2
fi

git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${git_root}" ]]; then
  echo "[git-topology-registry] Not inside a git repository." >&2
  exit 2
fi

git_common_dir="$(git rev-parse --git-common-dir)"
canonical_root="$(cd "${git_common_dir}" && cd .. && pwd -P)"
current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
canonical_branch="${WORKTREE_SKILL_CANONICAL_BRANCH:-main}"
state_dir="${git_common_dir}/topology-registry"
state_file="${state_dir}/health.env"
draft_file="${state_dir}/registry.draft.md"
backup_dir="${state_dir}/backups"
lock_dir="${state_dir}/lock"
lock_owner_file="${lock_dir}/owner.env"
lock_wait_attempts="${GIT_TOPOLOGY_REGISTRY_LOCK_WAIT_ATTEMPTS:-150}"
intent_rel="${WORKTREE_SKILL_TOPOLOGY_INTENT:-docs/GIT-TOPOLOGY-INTENT.yaml}"
doc_rel="${WORKTREE_SKILL_TOPOLOGY_DOC:-docs/GIT-TOPOLOGY-REGISTRY.md}"
intent_file="${git_root}/${intent_rel}"
registry_doc="${git_root}/${doc_rel}"
tmp_dir=""
lock_held=false
default_missing_intent="needs-decision"

intent_records_file=""
seen_subjects_file=""
worktrees_file=""
worktree_branches_file=""
local_branches_file=""
remote_branches_file=""
orphan_records_file=""
expected_doc_file=""

cleanup() {
  if [[ "${lock_held}" == "true" ]]; then
    rm -f "${lock_owner_file}" 2>/dev/null || true
    rmdir "${lock_dir}" 2>/dev/null || true
    lock_held=false
  fi
  if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}

trap cleanup EXIT

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ensure_tmp_dir() {
  if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
    return
  fi

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-topology-registry.XXXXXX")"
  intent_records_file="${tmp_dir}/intent-records.tsv"
  seen_subjects_file="${tmp_dir}/seen-subjects.tsv"
  worktrees_file="${tmp_dir}/worktrees.tsv"
  worktree_branches_file="${tmp_dir}/worktree-branches.txt"
  local_branches_file="${tmp_dir}/local-branches.tsv"
  remote_branches_file="${tmp_dir}/remote-branches.tsv"
  orphan_records_file="${tmp_dir}/orphan-records.tsv"
  expected_doc_file="${tmp_dir}/registry.md"

  : > "${intent_records_file}"
  : > "${seen_subjects_file}"
  : > "${worktrees_file}"
  : > "${worktree_branches_file}"
  : > "${local_branches_file}"
  : > "${remote_branches_file}"
  : > "${orphan_records_file}"
}

ensure_state_dir() {
  mkdir -p "${state_dir}"
}

write_lock_metadata() {
  local host_name=""

  host_name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"

  cat > "${lock_owner_file}" <<EOF
pid=$$
ppid=${PPID:-unknown}
action=${action}
branch=${current_branch:-detached}
cwd=${PWD}
git_root=${git_root}
host=${host_name}
started_at=$(now_utc)
EOF
}

lock_owner_value() {
  local key="$1"

  if [[ ! -f "${lock_owner_file}" ]]; then
    return 1
  fi

  awk -F= -v key="${key}" '$1 == key { sub($1 FS, ""); print; exit }' "${lock_owner_file}"
}

lock_dir_last_modified() {
  if [[ ! -d "${lock_dir}" ]]; then
    return 1
  fi

  if stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "${lock_dir}" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "${lock_dir}"
    return 0
  fi

  if stat -c '%y' "${lock_dir}" >/dev/null 2>&1; then
    stat -c '%y' "${lock_dir}"
    return 0
  fi

  return 1
}

print_lock_diagnostics() {
  local owner_pid=""
  local owner_branch=""
  local owner_cwd=""
  local owner_action=""
  local owner_host=""
  local owner_started_at=""
  local lock_modified_at=""

  if [[ ! -f "${lock_owner_file}" ]]; then
    echo "[git-topology-registry] Lock owner metadata is unavailable." >&2
    lock_modified_at="$(lock_dir_last_modified || true)"
    if [[ -n "${lock_modified_at}" ]]; then
      echo "[git-topology-registry] Lock directory last modified: ${lock_modified_at}" >&2
    fi
    echo "[git-topology-registry] This usually means a sibling worktree is running an older topology script or a previous refresh/doctor exited before writing owner metadata." >&2
    echo "[git-topology-registry] Verify active refresh/doctor commands in sibling worktrees; if none are active, remove: ${lock_dir}" >&2
    return 0
  fi

  owner_pid="$(lock_owner_value pid || true)"
  owner_branch="$(lock_owner_value branch || true)"
  owner_cwd="$(lock_owner_value cwd || true)"
  owner_action="$(lock_owner_value action || true)"
  owner_host="$(lock_owner_value host || true)"
  owner_started_at="$(lock_owner_value started_at || true)"

  [[ -n "${owner_pid}" ]] && echo "[git-topology-registry] Lock owner pid: ${owner_pid}" >&2
  [[ -n "${owner_action}" ]] && echo "[git-topology-registry] Lock owner action: ${owner_action}" >&2
  [[ -n "${owner_branch}" ]] && echo "[git-topology-registry] Lock owner branch: ${owner_branch}" >&2
  [[ -n "${owner_cwd}" ]] && echo "[git-topology-registry] Lock owner cwd: ${owner_cwd}" >&2
  [[ -n "${owner_host}" ]] && echo "[git-topology-registry] Lock owner host: ${owner_host}" >&2
  [[ -n "${owner_started_at}" ]] && echo "[git-topology-registry] Lock owner started_at: ${owner_started_at}" >&2

  if [[ -n "${owner_pid}" && ( -z "${owner_host}" || "${owner_host}" == "unknown" || "${owner_host}" == "$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')" ) ]]; then
    if kill -0 "${owner_pid}" 2>/dev/null; then
      echo "[git-topology-registry] Lock owner process is still alive." >&2
    else
      echo "[git-topology-registry] Lock owner pid is not running; stale lock is likely." >&2
      echo "[git-topology-registry] After verifying no sibling refresh/doctor is active, remove: ${lock_dir}" >&2
    fi
  fi
}

acquire_lock() {
  local attempts=0
  local mkdir_error=""
  ensure_state_dir

  while true; do
    mkdir_error=""
    if mkdir_error="$(mkdir "${lock_dir}" 2>&1)"; then
      lock_held=true
      write_lock_metadata
      return 0
    fi

    if [[ ! -d "${lock_dir}" ]]; then
      echo "[git-topology-registry] Cannot create lock directory: ${lock_dir}" >&2
      if [[ -n "${mkdir_error}" ]]; then
        echo "[git-topology-registry] mkdir error: ${mkdir_error}" >&2
      fi
      echo "[git-topology-registry] The shared topology state is not writable from this session." >&2
      echo "[git-topology-registry] This usually means the repo common .git directory is outside the current sandbox or permission boundary." >&2
      echo "[git-topology-registry] Re-run this command with approval/escalation or from a worktree that can write ${git_common_dir}." >&2
      exit 1
    fi

    attempts=$((attempts + 1))
    if [[ "${attempts}" -ge "${lock_wait_attempts}" ]]; then
      echo "[git-topology-registry] Timed out waiting for lock: ${lock_dir}" >&2
      echo "[git-topology-registry] Another refresh/doctor operation may still be running in a sibling worktree." >&2
      print_lock_diagnostics
      exit 1
    fi
    sleep 0.1
  done
}

hash_file() {
  local target="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${target}" | awk '{print $1}'
  else
    shasum -a 256 "${target}" | awk '{print $1}'
  fi
}

trim_leading_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s\n' "${value}"
}

normalize_scalar() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s\n' "${value}"
}

normalize_subject_key() {
  local subject_type="$1"
  local subject_key="$2"

  if [[ "${subject_type}" == "worktree" && "${subject_key}" =~ ^parallel-feature-([0-9]{3})$ ]]; then
    printf 'primary-feature-%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  printf '%s\n' "${subject_key}"
}

valid_subject_type() {
  case "$1" in
    branch|worktree|remote)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

valid_intent() {
  case "$1" in
    active|historical|extract-only|cleanup-candidate|protected|needs-decision)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_missing_intent() {
  local value="$1"

  if valid_intent "${value}"; then
    printf '%s\n' "${value}"
  else
    printf 'needs-decision\n'
  fi
}

normalize_record_intent() {
  local value="$1"
  local fallback="$2"

  fallback="$(normalize_missing_intent "${fallback}")"

  if valid_intent "${value}"; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${fallback}"
  fi
}

slugify() {
  local value="$1"
  printf '%s' "${value}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's|/|-|g; s|[^a-z0-9._-]+|-|g; s|-+|-|g; s|^-||; s|-$||'
}

escape_md_cell() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//|/\\|}"
  printf '%s\n' "${value}"
}

note_or_default() {
  local note="$1"
  local fallback="$2"
  if [[ -n "${note}" ]]; then
    printf '%s\n' "${note}"
  else
    printf '%s\n' "${fallback}"
  fi
}

parse_intent_sidecar() {
  local current_type=""
  local current_key=""
  local current_intent=""
  local current_note=""
  local current_pr=""
  local line=""

  ensure_tmp_dir
  : > "${intent_records_file}"
  default_missing_intent="needs-decision"

  if [[ ! -f "${intent_file}" ]]; then
    return
  fi

  flush_record() {
    local normalized_intent=""

    if [[ -z "${current_type}" || -z "${current_key}" ]]; then
      return
    fi

    if ! valid_subject_type "${current_type}"; then
      return
    fi

    normalized_intent="$(normalize_record_intent "${current_intent}" "${default_missing_intent}")"

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "${current_type}" \
      "${current_key}" \
      "${normalized_intent}" \
      "${current_note}" \
      "${current_pr}" >> "${intent_records_file}"
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      defaults:|records:|"")
        continue
        ;;
      "  missing_intent:"*)
        default_missing_intent="$(normalize_scalar "$(trim_leading_spaces "${line#*:}")")"
        ;;
      "  - subject_type:"*)
        flush_record
        current_type="$(normalize_scalar "$(trim_leading_spaces "${line#*:}")")"
        current_key=""
        current_intent=""
        current_note=""
        current_pr=""
        ;;
      "    subject_key:"*)
        current_key="$(normalize_scalar "$(trim_leading_spaces "${line#*:}")")"
        current_key="$(normalize_subject_key "${current_type}" "${current_key}")"
        ;;
      "    intent:"*)
        current_intent="$(normalize_scalar "$(trim_leading_spaces "${line#*:}")")"
        ;;
      "    note:"*)
        current_note="$(normalize_scalar "$(trim_leading_spaces "${line#*:}")")"
        ;;
      "    pr:"*)
        current_pr="$(normalize_scalar "$(trim_leading_spaces "${line#*:}")")"
        ;;
    esac
  done < "${intent_file}"

  default_missing_intent="$(normalize_missing_intent "${default_missing_intent}")"
  flush_record
  sort -t $'\t' -k1,1 -k2,2 "${intent_records_file}" -o "${intent_records_file}"
}

lookup_intent_field() {
  local subject_type="$1"
  local subject_key="$2"
  local field_index="$3"

  awk -F '\t' -v subject_type="${subject_type}" -v subject_key="${subject_key}" -v field_index="${field_index}" '
    $1 == subject_type && $2 == subject_key {
      print $field_index
      found = 1
      exit 0
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${intent_records_file}"
}

record_seen_subject() {
  local subject_type="$1"
  local subject_key="$2"
  printf '%s\t%s\n' "${subject_type}" "${subject_key}" >> "${seen_subjects_file}"
}

orphan_intent_count() {
  if [[ ! -s "${orphan_records_file}" ]]; then
    echo 0
    return
  fi

  awk 'END { print NR + 0 }' "${orphan_records_file}"
}

collect_orphan_records() {
  ensure_tmp_dir
  : > "${orphan_records_file}"

  if [[ ! -s "${intent_records_file}" ]]; then
    return
  fi

  awk -F '\t' '
    NR == FNR {
      seen[$1 FS $2] = 1
      next
    }
    !(($1 FS $2) in seen) {
      print $0
    }
  ' "${seen_subjects_file}" "${intent_records_file}" > "${orphan_records_file}"

  if [[ -s "${orphan_records_file}" ]]; then
    sort -t $'\t' -k1,1 -k2,2 "${orphan_records_file}" -o "${orphan_records_file}"
  fi
}

derive_worktree_id() {
  local raw_path="$1"
  local branch="$2"

  if [[ "${raw_path}" == "${canonical_root}" ]]; then
    printf 'primary-root\n'
    return
  fi

  if [[ "${branch}" =~ ^([0-9]{3})- ]]; then
    printf 'primary-feature-%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "${branch}" == codex/* ]]; then
    slugify "${branch}"
    return
  fi

  if [[ "${branch}" == feat/* ]]; then
    slugify "${branch#feat/}"
    return
  fi

  if [[ "${branch}" == test/* ]]; then
    slugify "${branch}"
    return
  fi

  slugify "$(basename "${raw_path}")"
}

derive_location_class() {
  local raw_path="$1"
  local branch="$2"

  if [[ "${raw_path}" == "${canonical_root}" ]]; then
    printf 'primary\n'
    return
  fi

  if [[ "${raw_path}" == *"/.codex/worktrees/"* ]]; then
    printf 'codex-managed\n'
    return
  fi

  if [[ "${branch}" =~ ^([0-9]{3})- ]]; then
    printf 'dedicated-feature-worktree\n'
    return
  fi

  printf 'sibling-worktree\n'
}

default_worktree_note() {
  local intent="$1"
  local branch="$2"
  local location_class="$3"

  case "${intent}" in
    active)
      if [[ "${location_class}" == "primary" ]]; then
        printf 'Canonical root worktree\n'
      elif [[ "${location_class}" == "dedicated-feature-worktree" ]]; then
        printf 'Active authoritative worktree for %s\n' "${branch}"
      else
        printf 'Active worktree for %s\n' "${branch}"
      fi
      ;;
    protected)
      printf 'Protected worktree; exclude from cleanup\n'
      ;;
    historical)
      printf 'Historical worktree\n'
      ;;
    cleanup-candidate)
      printf 'Review before cleanup\n'
      ;;
    extract-only)
      printf 'Source-only worktree\n'
      ;;
    *)
      printf 'Needs decision\n'
      ;;
  esac
}

default_branch_note() {
  local branch="$1"
  local tracking_state="$2"
  local has_worktree="$3"
  local intent="$4"

  case "${intent}" in
    active)
      if [[ "${branch}" == "${canonical_branch}" ]]; then
        printf 'Canonical source of truth\n'
      elif [[ "${has_worktree}" == "true" ]]; then
        printf 'Dedicated worktree exists\n'
      else
        printf 'Active branch\n'
      fi
      ;;
    protected)
      printf 'Protected branch; review before cleanup\n'
      ;;
    historical)
      if [[ "${tracking_state}" == "gone" ]]; then
        printf 'Historical branch with missing upstream\n'
      else
        printf 'Historical branch\n'
      fi
      ;;
    cleanup-candidate)
      printf 'Cleanup candidate\n'
      ;;
    extract-only)
      printf 'Extraction source only\n'
      ;;
    *)
      if [[ "${tracking_state}" == "gone" ]]; then
        printf 'Tracking ref is gone; needs decision\n'
      else
        printf 'Needs decision\n'
      fi
      ;;
  esac
}

default_remote_note() {
  local remote_ref="$1"
  local intent="$2"

  case "${intent}" in
    active)
      printf 'Active remote branch\n'
      ;;
    protected)
      printf 'Protected remote branch; exclude from cleanup\n'
      ;;
    historical)
      printf 'Historical remote branch\n'
      ;;
    cleanup-candidate)
      printf 'Cleanup candidate remote branch\n'
      ;;
    extract-only)
      printf 'Extraction source remote branch\n'
      ;;
    *)
      printf 'Needs decision\n'
      ;;
  esac
}

collect_worktrees() {
  local line=""
  local raw_path=""
  local branch=""

  ensure_tmp_dir
  : > "${worktrees_file}"
  : > "${worktree_branches_file}"

  flush_worktree() {
    local worktree_id=""
    local location_class=""
    local intent=""
    local note=""
    local pr=""

    if [[ -z "${raw_path}" ]]; then
      return
    fi

    if [[ -z "${branch}" ]]; then
      branch="DETACHED"
    fi

    worktree_id="$(derive_worktree_id "${raw_path}" "${branch}")"
    location_class="$(derive_location_class "${raw_path}" "${branch}")"
    intent="$(lookup_intent_field "worktree" "${worktree_id}" 3 2>/dev/null || true)"
    note="$(lookup_intent_field "worktree" "${worktree_id}" 4 2>/dev/null || true)"
    pr="$(lookup_intent_field "worktree" "${worktree_id}" 5 2>/dev/null || true)"

    if [[ -z "${intent}" ]]; then
      intent="${default_missing_intent}"
    fi
    note="$(note_or_default "${note}" "$(default_worktree_note "${intent}" "${branch}" "${location_class}")")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${worktree_id}" \
      "${branch}" \
      "${location_class}" \
      "${note}" \
      "${raw_path}" \
      "${intent}" \
      "${pr}" >> "${worktrees_file}"

    record_seen_subject "worktree" "${worktree_id}"

    if [[ "${branch}" != "DETACHED" ]]; then
      printf '%s\n' "${branch}" >> "${worktree_branches_file}"
    fi
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      "")
        flush_worktree
        raw_path=""
        branch=""
        ;;
      worktree\ *)
        raw_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      branch\ *)
        branch="${line#branch }"
        ;;
    esac
  done < <(git worktree list --porcelain; printf '\n')

  sort -t $'\t' -k1,1 "${worktrees_file}" -o "${worktrees_file}"
  sort -u "${worktree_branches_file}" -o "${worktree_branches_file}"
}

branch_has_worktree() {
  local branch="$1"
  if [[ ! -s "${worktree_branches_file}" ]]; then
    return 1
  fi
  grep -Fxq "${branch}" "${worktree_branches_file}"
}

tracking_state_for() {
  local upstream="$1"

  if [[ -z "${upstream}" ]]; then
    printf 'none\n'
    return
  fi

  if git show-ref --verify --quiet "refs/remotes/${upstream}"; then
    printf 'tracking\n'
    return
  fi

  if git show-ref --verify --quiet "refs/heads/${upstream}"; then
    printf 'tracking\n'
    return
  fi

  printf 'gone\n'
}

collect_local_branches() {
  local branch=""
  local upstream=""
  local tracking_state=""
  local has_worktree=""
  local intent=""
  local note=""
  local pr=""
  local sort_group=""

  ensure_tmp_dir
  : > "${local_branches_file}"

  while IFS=' ' read -r branch upstream || [[ -n "${branch}" ]]; do
    tracking_state="$(tracking_state_for "${upstream}")"
    has_worktree="false"
    if branch_has_worktree "${branch}"; then
      has_worktree="true"
    fi

    intent="$(lookup_intent_field "branch" "${branch}" 3 2>/dev/null || true)"
    note="$(lookup_intent_field "branch" "${branch}" 4 2>/dev/null || true)"
    pr="$(lookup_intent_field "branch" "${branch}" 5 2>/dev/null || true)"

    if [[ -z "${intent}" ]]; then
      intent="${default_missing_intent}"
    fi
    note="$(note_or_default "${note}" "$(default_branch_note "${branch}" "${tracking_state}" "${has_worktree}" "${intent}")")"

    if [[ "${branch}" == "${canonical_branch}" ]]; then
      sort_group="0"
    elif [[ "${has_worktree}" == "true" ]]; then
      sort_group="1"
    else
      sort_group="2"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${sort_group}" \
      "${branch}" \
      "${upstream}" \
      "${tracking_state}" \
      "${has_worktree}" \
      "${note}" \
      "${intent}" >> "${local_branches_file}"

    record_seen_subject "branch" "${branch}"
  done < <(git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads)

  sort -t $'\t' -k1,1 -k2,2 "${local_branches_file}" -o "${local_branches_file}"
}

collect_remote_branches() {
  local remote_ref=""
  local branch=""
  local intent=""
  local note=""
  local pr=""

  ensure_tmp_dir
  : > "${remote_branches_file}"

  while IFS= read -r remote_ref || [[ -n "${remote_ref}" ]]; do
    if [[ -z "${remote_ref}" || "${remote_ref}" == "origin/HEAD" || "${remote_ref}" == "origin/${canonical_branch}" ]]; then
      continue
    fi

    if git merge-base --is-ancestor "${remote_ref}" "refs/remotes/origin/${canonical_branch}" 2>/dev/null; then
      continue
    fi

    branch="${remote_ref#origin/}"
    intent="$(lookup_intent_field "remote" "${remote_ref}" 3 2>/dev/null || true)"
    note="$(lookup_intent_field "remote" "${remote_ref}" 4 2>/dev/null || true)"
    pr="$(lookup_intent_field "remote" "${remote_ref}" 5 2>/dev/null || true)"

    if [[ -z "${intent}" ]]; then
      intent="${default_missing_intent}"
    fi
    note="$(note_or_default "${note}" "$(default_remote_note "${remote_ref}" "${intent}")")"

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "${remote_ref}" \
      "${branch}" \
      "${note}" \
      "${intent}" \
      "${pr}" >> "${remote_branches_file}"

    record_seen_subject "remote" "${remote_ref}"
  done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)

  sort -t $'\t' -k1,1 "${remote_branches_file}" -o "${remote_branches_file}"
}

render_registry_markdown() {
  local orphan_count="$1"
  local worktree_id=""
  local branch=""
  local location_class=""
  local note=""
  local raw_path=""
  local intent=""
  local tracking=""
  local tracking_state=""
  local has_worktree=""
  local remote_ref=""
  local remote_branch=""
  local orphan_type=""
  local orphan_key=""
  local orphan_intent=""
  local orphan_note=""
  local orphan_pr=""
  local policy_line=""

  ensure_tmp_dir

  {
    cat <<'EOF'
# Git Topology Registry

**Status**: Generated artifact from live git topology and reviewed intent sidecar
**Scope**: Canonical maintainer workstation snapshot
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.
**Refresh**: `scripts/git-topology-registry.sh refresh --write-doc`
**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.

## Current Worktrees

| Worktree ID | Branch | Location Class | Status |
|---|---|---|---|
EOF

    while IFS=$'\t' read -r worktree_id branch location_class note raw_path intent pr || [[ -n "${worktree_id}" ]]; do
      printf '| `%s` | `%s` | `%s` | %s |\n' \
        "$(escape_md_cell "${worktree_id}")" \
        "$(escape_md_cell "${branch}")" \
        "$(escape_md_cell "${location_class}")" \
        "$(escape_md_cell "${note}")"
    done < "${worktrees_file}"

    cat <<'EOF'

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
EOF

    while IFS= read -r local_branch_row || [[ -n "${local_branch_row}" ]]; do
      branch="$(printf '%s\n' "${local_branch_row}" | cut -f2)"
      tracking="$(printf '%s\n' "${local_branch_row}" | cut -f3)"
      tracking_state="$(printf '%s\n' "${local_branch_row}" | cut -f4)"
      note="$(printf '%s\n' "${local_branch_row}" | cut -f6)"

      case "${tracking_state}" in
        gone)
          tracking="gone"
          ;;
        none)
          tracking="none"
          ;;
      esac

      printf '| `%s` | `%s` | %s |\n' \
        "$(escape_md_cell "${branch}")" \
        "$(escape_md_cell "${tracking}")" \
        "$(escape_md_cell "${note}")"
    done < "${local_branches_file}"

    cat <<'EOF'

## Remote Branches Not Merged Into `origin/${canonical_branch}`

| Remote Branch | Current Intent |
|---|---|
EOF

    while IFS=$'\t' read -r remote_ref remote_branch note intent pr || [[ -n "${remote_ref}" ]]; do
      printf '| `%s` | %s |\n' \
        "$(escape_md_cell "${remote_ref}")" \
        "$(escape_md_cell "${note}")"
    done < "${remote_branches_file}"

    if [[ "${orphan_count}" -gt 0 ]]; then
      cat <<'EOF'

## Reviewed Intent Awaiting Reconciliation

| Subject Type | Subject Key | Intent | Note | PR |
|---|---|---|---|---|
EOF

      while IFS=$'\t' read -r orphan_type orphan_key orphan_intent orphan_note orphan_pr || [[ -n "${orphan_type}" ]]; do
        orphan_note="$(note_or_default "${orphan_note}" "Reviewed intent retained until topology or sidecar is reconciled.")"
        orphan_pr="$(note_or_default "${orphan_pr}" "-")"
        printf '| `%s` | `%s` | `%s` | %s | %s |\n' \
          "$(escape_md_cell "${orphan_type}")" \
          "$(escape_md_cell "${orphan_key}")" \
          "$(escape_md_cell "${orphan_intent}")" \
          "$(escape_md_cell "${orphan_note}")" \
          "$(escape_md_cell "${orphan_pr}")"
      done < "${orphan_records_file}"

      cat <<EOF

## Registry Warnings

- Reviewed intent contains ${orphan_count} orphan record(s); keep them until topology catches up or the sidecar is reviewed.
EOF
    fi

    cat <<'EOF'

## Operating Rules

1. `${canonical_branch}` remains the only operational source of truth.
2. If a branch has a dedicated worktree, treat that worktree as the authoritative place for edits.
3. Before deleting or merging branches, verify this registry and then verify live `git` state again.
4. If branch/worktree state changes, this artifact must be refreshed in the same session or at the next session boundary.
5. Live `git` state wins over this document if they diverge; refresh the registry instead of forcing git to match the doc.

## Source Commands

```bash
git worktree list --porcelain
git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads
git for-each-ref --format='%(refname:short)' refs/remotes/origin
```
EOF
  } > "${expected_doc_file}"
}

build_snapshot() {
  ensure_tmp_dir
  : > "${seen_subjects_file}"

  parse_intent_sidecar
  collect_worktrees
  collect_local_branches
  collect_remote_branches
  collect_orphan_records
  local orphan_count=""
  orphan_count="$(orphan_intent_count)"
  render_registry_markdown "${orphan_count}"
}

compute_current_hash() {
  local combined="${tmp_dir}/combined-snapshot.txt"
  {
    printf 'default_missing_intent=%s\n' "${default_missing_intent}"
    printf '\n[intent]\n'
    cat "${intent_records_file}"
    printf '\n[worktrees]\n'
    cat "${worktrees_file}"
    printf '\n[local_branches]\n'
    cat "${local_branches_file}"
    printf '\n[remote_branches]\n'
    cat "${remote_branches_file}"
    printf '\n[orphan_records]\n'
    cat "${orphan_records_file}"
  } > "${combined}"
  hash_file "${combined}"
}

current_doc_hash() {
  if [[ -f "${registry_doc}" ]]; then
    hash_file "${registry_doc}"
  else
    printf 'missing\n'
  fi
}

write_recovery_draft() {
  ensure_state_dir
  cp "${expected_doc_file}" "${draft_file}"
}

backup_registry_doc() {
  local backup_file=""

  if [[ ! -f "${registry_doc}" ]]; then
    printf '\n'
    return 0
  fi

  ensure_state_dir
  mkdir -p "${backup_dir}"
  backup_file="${backup_dir}/registry-$(date -u +%Y%m%dT%H%M%SZ).md"
  cp "${registry_doc}" "${backup_file}"
  printf '%s\n' "${backup_file}"
}

install_rendered_registry_doc() {
  local apply_file="${registry_doc}.tmp.$$"
  local backup_file=""

  write_recovery_draft
  backup_file="$(backup_registry_doc)"

  if ! cp "${expected_doc_file}" "${apply_file}"; then
    rm -f "${apply_file}"
    return 1
  fi

  if ! mv "${apply_file}" "${registry_doc}"; then
    rm -f "${apply_file}"
    return 1
  fi

  printf '%s\n' "${backup_file}"
}

docs_match_expected() {
  if [[ ! -f "${registry_doc}" ]]; then
    return 1
  fi
  cmp -s "${expected_doc_file}" "${registry_doc}"
}

write_health_state() {
  local health_status="$1"
  local current_hash="$2"
  local rendered_hash="$3"
  local document_hash="$4"
  local orphan_count="$5"
  local message="$6"

  ensure_state_dir
  cat > "${state_file}" <<EOF
status=${health_status}
current_hash=${current_hash}
rendered_hash=${rendered_hash}
document_hash=${document_hash}
orphan_records_count=${orphan_count}
last_success_at=$(now_utc)
last_error=
message=${message}
EOF
}

write_error_state() {
  local message="$1"
  ensure_state_dir
  cat > "${state_file}" <<EOF
status=error
current_hash=
rendered_hash=
document_hash=
orphan_records_count=
last_success_at=
last_error=${message}
message=${message}
EOF
}

prune_state_dir() {
  if [[ ! -d "${state_dir}" ]]; then
    return
  fi

  find "${state_dir}" -mindepth 1 -maxdepth 1 \
    ! -name 'health.env' \
    ! -name 'lock' \
    ! -name 'backups' \
    -exec rm -rf {} +
}

status_flow() {
  local current_hash=""
  local rendered_hash=""
  local document_hash=""
  local orphan_count=""
  local health_status="ok"
  local message="registry matches rendered topology"

  build_snapshot
  current_hash="$(compute_current_hash)"
  rendered_hash="$(hash_file "${expected_doc_file}")"
  document_hash="$(current_doc_hash)"
  orphan_count="$(orphan_intent_count)"

  if ! docs_match_expected; then
    health_status="stale"
    message="registry document is stale; run scripts/git-topology-registry.sh refresh --write-doc"
  fi

  echo "repo_root=${git_root}"
  echo "git_common_dir=${git_common_dir}"
  echo "intent_file=${intent_file}"
  echo "registry_doc=${registry_doc}"
  echo "state_file=${state_file}"
  echo "status=${health_status}"
  echo "current_hash=${current_hash}"
  echo "rendered_hash=${rendered_hash}"
  echo "document_hash=${document_hash}"
  echo "orphan_records_count=${orphan_count}"
  echo "message=${message}"
}

check_flow() {
  local current_hash=""
  local rendered_hash=""
  local document_hash=""

  build_snapshot
  current_hash="$(compute_current_hash)"
  rendered_hash="$(hash_file "${expected_doc_file}")"
  document_hash="$(current_doc_hash)"

  if docs_match_expected; then
    echo "status=ok"
    echo "current_hash=${current_hash}"
    echo "rendered_hash=${rendered_hash}"
    echo "document_hash=${document_hash}"
    exit 0
  fi

  echo "status=stale"
  echo "current_hash=${current_hash}"
  echo "rendered_hash=${rendered_hash}"
  echo "document_hash=${document_hash}"
  echo "Run: scripts/git-topology-registry.sh refresh --write-doc"
  exit 1
}

refresh_flow() {
  local current_hash=""
  local rendered_hash=""
  local document_hash=""
  local orphan_count=""
  local stale=true
  local message=""
  local backup_file=""

  build_snapshot
  current_hash="$(compute_current_hash)"
  rendered_hash="$(hash_file "${expected_doc_file}")"
  document_hash="$(current_doc_hash)"
  orphan_count="$(orphan_intent_count)"

  if docs_match_expected; then
    stale=false
  fi

  if [[ "${write_doc}" != "true" ]]; then
    if [[ "${stale}" == "true" ]]; then
      echo "[git-topology-registry] Registry is stale. Run: scripts/git-topology-registry.sh refresh --write-doc" >&2
      exit 1
    fi
    echo "[git-topology-registry] Registry already matches live topology."
    exit 0
  fi

  acquire_lock
  build_snapshot
  current_hash="$(compute_current_hash)"
  rendered_hash="$(hash_file "${expected_doc_file}")"
  document_hash="$(current_doc_hash)"
  orphan_count="$(orphan_intent_count)"

  if docs_match_expected; then
    message="registry already current"
    write_health_state "ok" "${current_hash}" "${rendered_hash}" "${document_hash}" "${orphan_count}" "${message}"
    echo "[git-topology-registry] Registry already current."
    exit 0
  fi

  if ! backup_file="$(install_rendered_registry_doc)"; then
    message="registry refresh failed; recovery draft preserved at ${draft_file}"
    write_error_state "${message}"
    echo "[git-topology-registry] ${message}" >&2
    exit 1
  fi
  document_hash="$(hash_file "${registry_doc}")"
  message="registry refreshed from live git topology"
  if [[ -n "${backup_file}" ]]; then
    message="${message}; backup saved to ${backup_file}"
  fi
  write_health_state "ok" "${current_hash}" "${rendered_hash}" "${document_hash}" "${orphan_count}" "${message}"
  echo "[git-topology-registry] Registry refreshed."
}

doctor_flow() {
  local current_hash=""
  local rendered_hash=""
  local document_hash=""
  local orphan_count=""
  local message=""
  local backup_file=""

  acquire_lock
  if [[ "${prune}" == "true" ]]; then
    prune_state_dir
  fi

  build_snapshot
  current_hash="$(compute_current_hash)"
  rendered_hash="$(hash_file "${expected_doc_file}")"
  document_hash="$(current_doc_hash)"
  orphan_count="$(orphan_intent_count)"

  if docs_match_expected; then
    message="doctor found no drift"
    write_health_state "ok" "${current_hash}" "${rendered_hash}" "${document_hash}" "${orphan_count}" "${message}"
    echo "[git-topology-registry] Doctor found no drift."
    exit 0
  fi

  if [[ "${write_doc}" != "true" ]]; then
    write_recovery_draft
    message="doctor detected drift; draft saved to ${draft_file}; rerun with --write-doc to reconcile"
    write_health_state "stale" "${current_hash}" "${rendered_hash}" "${document_hash}" "${orphan_count}" "${message}"
    echo "[git-topology-registry] ${message}" >&2
    exit 1
  fi

  if ! backup_file="$(install_rendered_registry_doc)"; then
    message="doctor failed; recovery draft preserved at ${draft_file}"
    write_error_state "${message}"
    echo "[git-topology-registry] ${message}" >&2
    exit 1
  fi
  document_hash="$(hash_file "${registry_doc}")"
  message="doctor reconciled registry from live git topology"
  if [[ -n "${backup_file}" ]]; then
    message="${message}; backup saved to ${backup_file}"
  fi
  write_health_state "ok" "${current_hash}" "${rendered_hash}" "${document_hash}" "${orphan_count}" "${message}"
  echo "[git-topology-registry] Doctor reconciled registry."
}

case "${action}" in
  status)
    status_flow
    ;;
  check)
    check_flow
    ;;
  refresh)
    refresh_flow
    ;;
  doctor)
    doctor_flow
    ;;
esac
