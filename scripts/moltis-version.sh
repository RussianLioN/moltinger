#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_DEV="$PROJECT_ROOT/docker-compose.yml"
COMPOSE_PROD="$PROJECT_ROOT/docker-compose.prod.yml"
MOLTIS_IMAGE_PREFIX="ghcr.io/moltis-org/moltis:"

usage() {
    cat <<'EOF'
Usage: scripts/moltis-version.sh {version|image|assert-tracked}

Commands:
  version         Print the tracked Moltis version from compose files
  image           Print the tracked Moltis image reference from compose files
  assert-tracked  Fail unless docker-compose.yml and docker-compose.prod.yml
                  resolve to the same pinned Moltis image (not latest)
EOF
}

extract_image_ref_from_file() {
    local file="$1"
    local line=""

    if [[ ! -f "$file" ]]; then
        echo "Compose file not found: $file" >&2
        return 1
    fi

    line="$(grep -E '^[[:space:]]*image:[[:space:]]*["'\'']?ghcr\.io/moltis-org/moltis:' "$file" | head -n 1 || true)"
    line="${line#*image:}"
    line="$(printf '%s\n' "$line" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//')"

    if [[ -z "$line" ]]; then
        echo "No Moltis image reference found in $file" >&2
        return 1
    fi

    printf '%s\n' "$line"
}

normalize_version_from_image_ref() {
    local image_ref="$1"
    local suffix="${image_ref#${MOLTIS_IMAGE_PREFIX}}"

    if [[ "$image_ref" != "${MOLTIS_IMAGE_PREFIX}"* ]]; then
        echo "Unsupported Moltis image reference: $image_ref" >&2
        return 1
    fi

    if [[ "$suffix" =~ ^\$\{MOLTIS_VERSION:-([^}]+)\}$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "$suffix" =~ ^\$\{MOLTIS_VERSION-([^}]+)\}$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "$suffix" == '${MOLTIS_VERSION}' || "$suffix" == '$MOLTIS_VERSION' ]]; then
        echo "Moltis image must include an explicit tag or a defaulted MOLTIS_VERSION expression" >&2
        return 1
    fi

    if [[ -z "$suffix" ]]; then
        echo "Tracked Moltis version is empty" >&2
        return 1
    fi

    printf '%s\n' "$suffix"
}

normalize_image_ref() {
    local image_ref="$1"
    local version=""

    version="$(normalize_version_from_image_ref "$image_ref")"
    printf '%s%s\n' "$MOLTIS_IMAGE_PREFIX" "$version"
}

tracked_moltis_image_ref() {
    local dev_ref prod_ref dev_normalized prod_normalized

    dev_ref="$(extract_image_ref_from_file "$COMPOSE_DEV")"
    prod_ref="$(extract_image_ref_from_file "$COMPOSE_PROD")"
    dev_normalized="$(normalize_image_ref "$dev_ref")"
    prod_normalized="$(normalize_image_ref "$prod_ref")"

    if [[ "$dev_normalized" != "$prod_normalized" ]]; then
        echo "Moltis image mismatch between compose files:" >&2
        echo "  $COMPOSE_DEV -> $dev_normalized" >&2
        echo "  $COMPOSE_PROD -> $prod_normalized" >&2
        return 1
    fi

    printf '%s\n' "$dev_normalized"
}

tracked_moltis_version() {
    local image_ref
    image_ref="$(tracked_moltis_image_ref)"
    printf '%s\n' "${image_ref#${MOLTIS_IMAGE_PREFIX}}"
}

assert_tracked_contract() {
    local version
    version="$(tracked_moltis_version)"

    if [[ -z "$version" ]]; then
        echo "Tracked Moltis version is empty" >&2
        return 1
    fi

    if [[ "$version" == "latest" ]]; then
        echo "Tracked Moltis version must be pinned in git; 'latest' is forbidden" >&2
        return 1
    fi
}

main() {
    local command="${1:-}"

    case "$command" in
        version)
            assert_tracked_contract
            tracked_moltis_version
            ;;
        image)
            assert_tracked_contract
            tracked_moltis_image_ref
            ;;
        assert-tracked)
            assert_tracked_contract
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
