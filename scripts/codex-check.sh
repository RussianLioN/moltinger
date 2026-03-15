#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/codex-check.sh
  ./scripts/codex-check.sh --ci
  ./scripts/codex-check.sh --no-skills

Options:
  --ci         Skip Codex skill-bridge checks for CI environments
  --no-skills  Skip Codex skill-bridge checks locally
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SKIP_SKILLS=0

for arg in "$@"; do
  case "${arg}" in
    --ci|--no-skills)
      SKIP_SKILLS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

require_file() {
  local path="$1"
  if [[ ! -f "${REPO_ROOT}/${path}" ]]; then
    log_error "Missing required file: ${path}"
    return 1
  fi

  log_success "Found required file: ${path}"
}

assert_contains() {
  local path="$1"
  local pattern="$2"
  local description="$3"

  if ! grep -Fq -- "${pattern}" "${REPO_ROOT}/${path}"; then
    log_error "Missing ${description} in ${path}"
    return 1
  fi

  log_success "Verified ${description} in ${path}"
}

check_required_files() {
  log_info "Checking required Codex governance files..."

  local files=(
    "AGENTS.md"
    "bin/bd"
    ".ai/instructions/shared-core.md"
    ".ai/instructions/codex-adapter.md"
    ".ai/AGENTS.md"
    ".beads/AGENTS.md"
    ".claude/AGENTS.md"
    ".github/AGENTS.md"
    ".github/workflows/codex-policy.yml"
    ".specify/AGENTS.md"
    "config/AGENTS.md"
    "docs/AGENTS.md"
    "docs/CODEX-OPERATING-MODEL.md"
    "docs/GIT-TOPOLOGY-REGISTRY.md"
    "docs/plans/codex-rollout-rollback.md"
    "knowledge/AGENTS.md"
    "scripts/AGENTS.md"
    "specs/AGENTS.md"
    "tests/AGENTS.md"
    "scripts/codex-check.sh"
    "scripts/codex-profile-launch.sh"
    "scripts/beads-resolve-db.sh"
    "scripts/beads-worktree-localize.sh"
  )

  local failures=0
  for path in "${files[@]}"; do
    require_file "${path}" || failures=1
  done

  return "${failures}"
}

check_instruction_references() {
  log_info "Checking source instruction references..."

  local failures=0
  assert_contains ".ai/instructions/shared-core.md" "Speckit Artifact Guard" "root Speckit guard" || failures=1
  assert_contains ".ai/instructions/shared-core.md" "docs/GIT-TOPOLOGY-REGISTRY.md" "topology registry reference" || failures=1
  if grep -Fq -- "./scripts/bd-local.sh sync" "${REPO_ROOT}/.ai/instructions/shared-core.md" || \
     grep -Fq -- "bd sync" "${REPO_ROOT}/.ai/instructions/shared-core.md"; then
    log_success "Verified safe Beads sync guidance in .ai/instructions/shared-core.md"
  else
    log_error "Missing safe Beads sync guidance in .ai/instructions/shared-core.md"
    failures=1
  fi
  assert_contains ".ai/instructions/codex-adapter.md" "docs/CODEX-OPERATING-MODEL.md" "operating model reference" || failures=1
  assert_contains ".ai/instructions/codex-adapter.md" "make codex-check" "Codex governance check command" || failures=1
  if grep -Fq -- "./scripts/bd-local.sh" "${REPO_ROOT}/docs/CODEX-OPERATING-MODEL.md" || \
     grep -Fq -- "plain `bd`" "${REPO_ROOT}/docs/CODEX-OPERATING-MODEL.md"; then
    log_success "Verified local Beads ownership guidance in docs/CODEX-OPERATING-MODEL.md"
  else
    log_error "Missing local Beads ownership guidance in docs/CODEX-OPERATING-MODEL.md"
    failures=1
  fi

  return "${failures}"
}

check_deprecated_references() {
  log_info "Checking for deprecated Codex/model references..."

  local pattern='gpt-5\.2(-codex)?|gpt 5\.2|openai-codex|providers\.openai-codex'
  local matches
  local filtered_matches

  if command -v rg >/dev/null 2>&1; then
    matches="$(cd "${REPO_ROOT}" && rg -n -S "${pattern}" . -g '!scripts/codex-check.sh' || true)"
  else
    matches="$(cd "${REPO_ROOT}" && grep -RInE --exclude-dir=.git --exclude=codex-check.sh "${pattern}" . || true)"
  fi

  filtered_matches="$(printf '%s\n' "${matches}" | grep -Ev '^(\./)?(config/clawdiy/openclaw\.json|tests/static/test_config_validation\.sh):' || true)"

  if [[ -n "${filtered_matches}" ]]; then
    log_error "Deprecated references found:"
    printf '%s\n' "${filtered_matches}"
    return 1
  fi

  log_success "No deprecated Codex/model references found"
}

main() {
  cd "${REPO_ROOT}"

  check_required_files

  log_info "Checking generated root instructions..."
  "${SCRIPT_DIR}/sync-agent-instructions.sh" --check

  if [[ "${SKIP_SKILLS}" -eq 1 ]]; then
    log_warn "Skipping Codex skill bridge check"
  else
    log_info "Checking Codex skill bridge..."
    "${SCRIPT_DIR}/sync-claude-skills-to-codex.sh" --check
  fi

  check_instruction_references
  check_deprecated_references

  log_success "Codex governance checks passed"
}

main "$@"
