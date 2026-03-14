#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_MAIN="${COMPOSE_MAIN:-$PROJECT_ROOT/docker-compose.yml}"
COMPOSE_PROD="${COMPOSE_PROD:-$PROJECT_ROOT/docker-compose.prod.yml}"
IMAGE_REPO="ghcr.io/moltis-org/moltis"

usage() {
    cat <<'EOF'
Usage: scripts/moltis-version.sh <command>

Commands:
  version         Print normalized tracked Moltis version
  image           Print normalized tracked Moltis image
  policy          Print tracked policy: latest or release-tag
  report          Print a human-readable tracked version summary
  assert-tracked  Validate the tracked version contract
EOF
}

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

extract_image_from_compose() {
    local compose_file="$1"
    local line=""

    [[ -f "$compose_file" ]] || fail "Compose file not found: $compose_file"

    line="$(grep -E '^[[:space:]]*image:[[:space:]]*["'\'']?ghcr\.io/moltis-org/moltis:' "$compose_file" | head -n 1 || true)"
    [[ -n "$line" ]] || fail "Could not find Moltis image in $compose_file"

    line="${line#*image:}"
    line="$(printf '%s\n' "$line" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//')"
    [[ -n "$line" ]] || fail "Could not normalize Moltis image from $compose_file"

    printf '%s\n' "$line"
}

normalize_version_from_image() {
    local image="$1"
    local version=""

    [[ "$image" == "${IMAGE_REPO}:"* ]] || fail "Unsupported Moltis image reference: $image"
    version="${image#${IMAGE_REPO}:}"

    if [[ "$version" =~ ^\$\{MOLTIS_VERSION:-(.+)\}$ ]]; then
        version="${BASH_REMATCH[1]}"
    elif [[ "$version" =~ ^\$\{MOLTIS_VERSION-(.+)\}$ ]]; then
        version="${BASH_REMATCH[1]}"
    elif [[ "$version" == '${MOLTIS_VERSION}' || "$version" == '$MOLTIS_VERSION' ]]; then
        fail "Moltis image must include an explicit tag or a defaulted MOLTIS_VERSION expression"
    fi

    [[ -n "$version" ]] || fail "Resolved empty Moltis version from image: $image"
    printf '%s\n' "$version"
}

resolve_contract() {
    local main_image main_version prod_image prod_version

    main_image="$(extract_image_from_compose "$COMPOSE_MAIN")"
    prod_image="$(extract_image_from_compose "$COMPOSE_PROD")"

    main_version="$(normalize_version_from_image "$main_image")"
    prod_version="$(normalize_version_from_image "$prod_image")"

    if [[ "$main_version" != "$prod_version" ]]; then
        fail "Compose Moltis version mismatch: $COMPOSE_MAIN -> $main_version, $COMPOSE_PROD -> $prod_version"
    fi

    RESOLVED_VERSION="$main_version"
    RESOLVED_IMAGE="${IMAGE_REPO}:${RESOLVED_VERSION}"
    RESOLVED_POLICY="release-tag"

    if [[ "$RESOLVED_VERSION" == "latest" ]]; then
        RESOLVED_POLICY="latest"
    fi
}

command="${1:-}"

case "$command" in
    version)
        resolve_contract
        printf '%s\n' "$RESOLVED_VERSION"
        ;;
    image)
        resolve_contract
        printf '%s\n' "$RESOLVED_IMAGE"
        ;;
    policy)
        resolve_contract
        printf '%s\n' "$RESOLVED_POLICY"
        ;;
    report)
        resolve_contract
        printf 'Tracked Moltis Version: %s\n' "$RESOLVED_VERSION"
        printf 'Tracked Moltis Image: %s\n' "$RESOLVED_IMAGE"
        printf 'Tracked Moltis Policy: %s\n' "$RESOLVED_POLICY"
        printf 'Tracked Source: %s + %s\n' "$(basename "$COMPOSE_MAIN")" "$(basename "$COMPOSE_PROD")"
        ;;
    assert-tracked)
        resolve_contract
        ;;
    -h|--help|help|"")
        usage
        if [[ -z "$command" ]]; then
            exit 2
        fi
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
