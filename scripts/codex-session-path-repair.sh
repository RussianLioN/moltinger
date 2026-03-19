#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

apply_changes=false
repair_git_worktrees=false
codex_home="${CODEX_HOME:-$HOME/.codex}"
old_main="/Users/rl/coding/moltinger"
new_main="/Users/rl/coding/moltinger/moltinger-main"
moved_root="/Users/rl/coding/moltinger"

usage() {
  cat <<'USAGE'
Repair Codex session CWD paths after manual repository/worktree relocation.

Usage:
  scripts/codex-session-path-repair.sh [options]

Options:
  --apply                  Apply updates (default is dry-run)
  --repair-git-worktrees   Also run git worktree repair for discovered moved worktrees
  --codex-home <path>      Codex home directory (default: $CODEX_HOME or ~/.codex)
  --old-main <path>        Previous canonical repo path
  --new-main <path>        New canonical repo path
  --moved-root <path>      Root directory that now contains moved worktrees
  -h, --help               Show this help

Examples:
  scripts/codex-session-path-repair.sh
  scripts/codex-session-path-repair.sh --apply
  scripts/codex-session-path-repair.sh --apply --repair-git-worktrees
USAGE
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

sql_escape() {
  local value="$1"
  printf "%s" "${value//\'/\'\'}"
}

count_threads_for_cwd() {
  local db="$1"
  local cwd="$2"
  local cwd_esc
  cwd_esc="$(sql_escape "$cwd")"
  sqlite3 -readonly "$db" "SELECT COUNT(*) FROM threads WHERE cwd='${cwd_esc}';"
}

count_archived_for_cwd() {
  local cwd="$1"
  shift
  local count=0
  local file first_line

  for file in "$@"; do
    first_line="$(head -n 1 "$file" 2>/dev/null || true)"
    [[ -n "$first_line" ]] || continue
    if printf '%s\n' "$first_line" | jq -e --arg cwd "$cwd" '
      .type == "session_meta" and (.payload.cwd // "") == $cwd
    ' >/dev/null 2>&1; then
      count=$((count + 1))
    fi
  done

  printf '%s\n' "$count"
}

run_git_worktree_repair() {
  local main_repo="$1"
  local root_dir="$2"
  local codex_root="$3"
  local dry_run="$4"
  local -a targets=()
  local -a unique_targets=()
  local -a failures=()
  local path
  local status=0
  declare -A seen=()

  [[ -d "$main_repo" ]] || {
    warn "Skip git worktree repair: new main path does not exist: $main_repo"
    return 0
  }

  if [[ -d "$root_dir" ]]; then
    while IFS= read -r path; do
      [[ -e "$path/.git" ]] || continue
      targets+=("$path")
    done < <(find "$root_dir" -mindepth 1 -maxdepth 1 -type d -name 'moltinger-*' | sort)
  fi

  if [[ -d "$codex_root/worktrees" ]]; then
    while IFS= read -r path; do
      [[ -e "$path/.git" ]] || continue
      targets+=("$path")
    done < <(find "$codex_root/worktrees" -mindepth 2 -maxdepth 2 -type d -name 'moltinger' | sort)
  fi

  for path in "$main_repo" "${targets[@]}"; do
    [[ -d "$path" ]] || continue
    if [[ -z "${seen[$path]:-}" ]]; then
      seen[$path]=1
      unique_targets+=("$path")
    fi
  done

  if [[ ${#unique_targets[@]} -eq 0 ]]; then
    warn "No git worktree paths discovered for repair."
    return 0
  fi

  log "Git worktree repair targets: ${#unique_targets[@]}"
  for path in "${unique_targets[@]}"; do
    printf '  - %s\n' "$path"
  done

  if [[ "$dry_run" == "true" ]]; then
    return 0
  fi

  for path in "${unique_targets[@]}"; do
    if git -C "$main_repo" worktree repair "$path" >/dev/null 2>&1; then
      log "Repaired worktree link: $path"
    else
      warn "Failed to repair worktree link: $path"
      failures+=("$path")
      status=1
    fi
  done

  local prunable_count
  prunable_count="$(git -C "$main_repo" worktree list --porcelain | rg -c '^prunable ' || true)"
  log "Remaining prunable entries: ${prunable_count}"

  if [[ ${#failures[@]} -gt 0 ]]; then
    warn "Worktree paths that still require manual attention:"
    for path in "${failures[@]}"; do
      printf '  - %s\n' "$path" >&2
    done
  fi

  return "$status"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply_changes=true
      shift
      ;;
    --repair-git-worktrees)
      repair_git_worktrees=true
      shift
      ;;
    --codex-home)
      [[ $# -ge 2 ]] || die "Missing value for --codex-home"
      codex_home="$2"
      shift 2
      ;;
    --old-main)
      [[ $# -ge 2 ]] || die "Missing value for --old-main"
      old_main="$2"
      shift 2
      ;;
    --new-main)
      [[ $# -ge 2 ]] || die "Missing value for --new-main"
      new_main="$2"
      shift 2
      ;;
    --moved-root)
      [[ $# -ge 2 ]] || die "Missing value for --moved-root"
      moved_root="$2"
      shift 2
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

require_cmd jq
require_cmd sqlite3

state_db="${codex_home}/state_5.sqlite"
archived_dir="${codex_home}/archived_sessions"

[[ -f "$state_db" ]] || die "Missing Codex DB: $state_db"
[[ -d "$archived_dir" ]] || die "Missing Codex archived sessions dir: $archived_dir"

shopt -s nullglob
archived_files=("${archived_dir}"/*.jsonl)
shopt -u nullglob

declare -A path_map=()

if [[ -d "$new_main" ]]; then
  path_map["$old_main"]="$new_main"
else
  warn "New main path not found, skip main remap candidate: $new_main"
fi

mapfile -t all_cwds < <(
  {
    sqlite3 -readonly "$state_db" "SELECT DISTINCT cwd FROM threads;"
    for file in "${archived_files[@]}"; do
      head -n 1 "$file" 2>/dev/null || true
    done | jq -r 'select(.type == "session_meta") | .payload.cwd // empty'
  } | awk 'NF' | sort -u
)

for cwd in "${all_cwds[@]}"; do
  if [[ "$cwd" == "${old_main}-"* ]]; then
    candidate="${moved_root}/$(basename "$cwd")"
    if [[ -d "$candidate" ]]; then
      path_map["$cwd"]="$candidate"
    fi
  fi
done

mapfile -t map_keys < <(printf '%s\n' "${!path_map[@]}" | sort)

if [[ ${#map_keys[@]} -eq 0 ]]; then
  log "No remap candidates found. Nothing to do."
  exit 0
fi

declare -a effective_map_keys=()

for old_path in "${map_keys[@]}"; do
  new_path="${path_map[$old_path]}"
  threads_count="$(count_threads_for_cwd "$state_db" "$old_path")"
  archived_count="$(count_archived_for_cwd "$old_path" "${archived_files[@]}")"
  if [[ "$threads_count" != "0" || "$archived_count" != "0" ]]; then
    effective_map_keys+=("$old_path")
    printf '  - %s -> %s (threads=%s, archived=%s)\n' \
      "$old_path" "$new_path" "$threads_count" "$archived_count"
  fi
done

if [[ ${#effective_map_keys[@]} -eq 0 ]]; then
  log "No remap candidates with actual references. Nothing to do."
  if [[ "$repair_git_worktrees" == "true" ]]; then
    run_git_worktree_repair "$new_main" "$moved_root" "$codex_home" true || true
  fi
  exit 0
fi

map_keys=("${effective_map_keys[@]}")
log "Detected remap candidates:"
for old_path in "${map_keys[@]}"; do
  new_path="${path_map[$old_path]}"
  threads_count="$(count_threads_for_cwd "$state_db" "$old_path")"
  archived_count="$(count_archived_for_cwd "$old_path" "${archived_files[@]}")"
  printf '  - %s -> %s (threads=%s, archived=%s)\n' \
    "$old_path" "$new_path" "$threads_count" "$archived_count"
done

if [[ "$apply_changes" != "true" ]]; then
  log "Dry-run complete. Re-run with --apply to write changes."
  if [[ "$repair_git_worktrees" == "true" ]]; then
    run_git_worktree_repair "$new_main" "$moved_root" "$codex_home" true || true
  fi
  exit 0
fi

timestamp="$(date '+%Y%m%d-%H%M%S')"
backup_dir="${codex_home}/backups/cwd-path-repair-${timestamp}"
backup_archived_dir="${backup_dir}/archived_sessions"
mkdir -p "$backup_archived_dir"

state_backup="${backup_dir}/state_5.sqlite"
state_backup_esc="$(sql_escape "$state_backup")"
sqlite3 "$state_db" ".backup '${state_backup_esc}'"
log "Backed up state DB to: $state_backup"

sql_updates="BEGIN IMMEDIATE;"
for old_path in "${map_keys[@]}"; do
  new_path="${path_map[$old_path]}"
  old_esc="$(sql_escape "$old_path")"
  new_esc="$(sql_escape "$new_path")"
  sql_updates+="UPDATE threads SET cwd='${new_esc}' WHERE cwd='${old_esc}';"
done
sql_updates+="COMMIT;"
sqlite3 "$state_db" "PRAGMA busy_timeout=5000;" >/dev/null
sqlite3 "$state_db" "$sql_updates"
log "Updated threads.cwd in state DB."

map_json='{}'
for old_path in "${map_keys[@]}"; do
  new_path="${path_map[$old_path]}"
  map_json="$(printf '%s\n' "$map_json" | jq -c --arg old "$old_path" --arg new "$new_path" '. + {($old): $new}')"
done

updated_files=0
for file in "${archived_files[@]}"; do
  first_line="$(head -n 1 "$file" 2>/dev/null || true)"
  [[ -n "$first_line" ]] || continue

  new_first_line="$(printf '%s\n' "$first_line" | jq -c --argjson mapping "$map_json" '
    if .type == "session_meta"
      and (.payload.cwd | type == "string")
      and ($mapping[.payload.cwd] != null)
    then .payload.cwd = $mapping[.payload.cwd]
    else .
    end
  ')"

  if [[ "$new_first_line" != "$first_line" ]]; then
    cp "$file" "${backup_archived_dir}/$(basename "$file")"
    temp_file="$(mktemp)"
    {
      printf '%s\n' "$new_first_line"
      tail -n +2 "$file"
    } > "$temp_file"
    mv "$temp_file" "$file"
    updated_files=$((updated_files + 1))
  fi
done
log "Updated archived session files: $updated_files"

if [[ "$repair_git_worktrees" == "true" ]]; then
  if run_git_worktree_repair "$new_main" "$moved_root" "$codex_home" false; then
    log "Git worktree repair completed."
  else
    warn "Git worktree repair completed with warnings."
  fi
fi

log "Post-migration top CWDs:"
sqlite3 -readonly "$state_db" '
  SELECT cwd, COUNT(*) AS n
  FROM threads
  GROUP BY cwd
  ORDER BY n DESC
  LIMIT 15;
'

log "Done. Backups stored in: $backup_dir"
