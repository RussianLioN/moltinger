#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MOLTIS_VERSION_HELPER="$PROJECT_ROOT/scripts/moltis-version.sh"
MOLTIS_IMAGE_PREFIX="${MOLTIS_IMAGE_PREFIX:-ghcr.io/moltis-org/moltis:}"

TRACKED_VERSION=""
LATEST_RELEASE_TAG=""
FORCE_MODE=false

usage() {
    cat <<'EOF'
Usage: scripts/moltis-update-proposal-resolver.sh \
  --tracked-version <tag> \
  --latest-release-tag <tag> \
  [--force]

Outputs shell-style key=value pairs suitable for appending to $GITHUB_OUTPUT.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tracked-version)
            TRACKED_VERSION="${2:-}"
            shift 2
            ;;
        --latest-release-tag)
            LATEST_RELEASE_TAG="${2:-}"
            shift 2
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-update-proposal-resolver.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$TRACKED_VERSION" || -z "$LATEST_RELEASE_TAG" ]]; then
    echo "moltis-update-proposal-resolver.sh: --tracked-version and --latest-release-tag are required" >&2
    usage >&2
    exit 2
fi

TRACKED_VERSION="$(bash "$MOLTIS_VERSION_HELPER" normalize-tag "$TRACKED_VERSION")"
CANDIDATE_VERSION="$(bash "$MOLTIS_VERSION_HELPER" normalize-tag "$LATEST_RELEASE_TAG")"
CANDIDATE_IMAGE="${MOLTIS_IMAGE_PREFIX}${CANDIDATE_VERSION}"
SHOULD_UPDATE=true
SKIP_REASON=""

if [[ "$CANDIDATE_VERSION" == "$TRACKED_VERSION" ]]; then
    SHOULD_UPDATE=false
    SKIP_REASON="tracked version already equals latest release candidate"
elif [[ "$FORCE_MODE" != "true" ]]; then
    NEWEST="$(printf '%s\n%s\n' "$TRACKED_VERSION" "$CANDIDATE_VERSION" | sort -V | tail -n1)"
    if [[ "$NEWEST" != "$CANDIDATE_VERSION" ]]; then
        SHOULD_UPDATE=false
        SKIP_REASON="latest release candidate is not newer than tracked version"
    fi
fi

if [[ "$SHOULD_UPDATE" == "true" ]] && ! docker manifest inspect "$CANDIDATE_IMAGE" >/dev/null 2>&1; then
    SHOULD_UPDATE=false
    SKIP_REASON="normalized GHCR tag ${CANDIDATE_IMAGE} is not pullable yet"
fi

printf 'tracked_version=%s\n' "$TRACKED_VERSION"
printf 'latest_release_tag=%s\n' "$LATEST_RELEASE_TAG"
printf 'candidate_version=%s\n' "$CANDIDATE_VERSION"
printf 'candidate_image=%s\n' "$CANDIDATE_IMAGE"
printf 'should_update=%s\n' "$SHOULD_UPDATE"
printf 'skip_reason=%s\n' "$SKIP_REASON"
