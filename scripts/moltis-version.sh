#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_DEV="$PROJECT_ROOT/docker-compose.yml"
COMPOSE_PROD="$PROJECT_ROOT/docker-compose.prod.yml"
MOLTIS_IMAGE_PREFIX="ghcr.io/moltis-org/moltis:"

usage() {
    cat <<'EOF'
Usage: scripts/moltis-version.sh {version|image|assert-tracked|normalize-tag|compare}

Commands:
  version         Print the tracked Moltis version from compose files
  image           Print the tracked Moltis image reference from compose files
  assert-tracked  Fail unless docker-compose.yml and docker-compose.prod.yml
                  resolve to the same pinned Moltis image (not latest)
  normalize-tag   Normalize an upstream release tag into a pullable GHCR tag
  compare         Compare two explicit release tags (-1 left<right, 0 eq, 1 left>right)
EOF
}

is_semver_release_tag() {
    local version="${1:-}"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z._-]+)?$ ]]
}

is_calendar_release_tag() {
    local version="${1:-}"
    [[ "$version" =~ ^20[0-9]{6}\.[0-9]{2}([-.][0-9A-Za-z._-]+)?$ ]]
}

is_explicit_release_tag() {
    local version="${1:-}"
    is_semver_release_tag "$version" || is_calendar_release_tag "$version"
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

normalize_release_tag() {
    local raw_tag="${1:-}"
    local normalized="${raw_tag#v}"

    if [[ -z "$raw_tag" ]]; then
        echo "Release tag is empty" >&2
        return 1
    fi

    if [[ "$normalized" == "latest" ]]; then
        echo "Explicit Moltis release tag required; 'latest' is not allowed here" >&2
        return 1
    fi

    if ! is_explicit_release_tag "$normalized"; then
        echo "Unsupported Moltis release tag format: $raw_tag" >&2
        return 1
    fi

    printf '%s\n' "$normalized"
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

assert_explicit_release_tag() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        echo "Tracked Moltis version is empty" >&2
        return 1
    fi

    if [[ "$version" == "latest" ]]; then
        echo "Tracked Moltis version must be an explicit GHCR release tag, not 'latest'" >&2
        return 1
    fi

    if [[ "$version" == v* ]]; then
        echo "Tracked Moltis version must use GHCR tag format without leading 'v' (example: 20260421.05)" >&2
        return 1
    fi

    if ! is_explicit_release_tag "$version"; then
        echo "Tracked Moltis version is not a supported explicit release tag: $version" >&2
        return 1
    fi
}

assert_tracked_contract() {
    local version
    version="$(tracked_moltis_version)"
    assert_explicit_release_tag "$version"
}

compare_release_tags() {
    local left_raw="${1:-}"
    local right_raw="${2:-}"
    local left=""
    local right=""
    local left_base=""
    local left_suffix=""
    local right_base=""
    local right_suffix=""
    local base_compare=""
    local newest=""
    local max_len=0
    local i=0
    local left_part=0
    local right_part=0
    local -a left_parts=()
    local -a right_parts=()

    left="$(normalize_release_tag "$left_raw")"
    right="$(normalize_release_tag "$right_raw")"

    if [[ "$left" == "$right" ]]; then
        printf '0\n'
        return 0
    fi

    if [[ "$left" =~ ^([0-9]+(\.[0-9]+)*)([-.]([0-9A-Za-z._-]+))?$ ]]; then
        left_base="${BASH_REMATCH[1]}"
        left_suffix="${BASH_REMATCH[4]:-}"
    else
        echo "Unsupported normalized release tag: $left" >&2
        return 1
    fi

    if [[ "$right" =~ ^([0-9]+(\.[0-9]+)*)([-.]([0-9A-Za-z._-]+))?$ ]]; then
        right_base="${BASH_REMATCH[1]}"
        right_suffix="${BASH_REMATCH[4]:-}"
    else
        echo "Unsupported normalized release tag: $right" >&2
        return 1
    fi

    IFS='.' read -r -a left_parts <<< "$left_base"
    IFS='.' read -r -a right_parts <<< "$right_base"

    max_len="${#left_parts[@]}"
    if (( ${#right_parts[@]} > max_len )); then
        max_len="${#right_parts[@]}"
    fi

    base_compare='0'
    for (( i = 0; i < max_len; i += 1 )); do
        left_part="${left_parts[i]:-0}"
        right_part="${right_parts[i]:-0}"

        if (( 10#$left_part > 10#$right_part )); then
            base_compare='1'
            break
        fi
        if (( 10#$left_part < 10#$right_part )); then
            base_compare='-1'
            break
        fi
    done

    if [[ "$base_compare" != "0" ]]; then
        printf '%s\n' "$base_compare"
        return 0
    fi

    if [[ -z "$left_suffix" && -z "$right_suffix" ]]; then
        printf '0\n'
        return 0
    fi

    if [[ -z "$left_suffix" ]]; then
        printf '1\n'
        return 0
    fi

    if [[ -z "$right_suffix" ]]; then
        printf '%s\n' '-1'
        return 0
    fi

    newest="$(printf '%s\n%s\n' "$left_suffix" "$right_suffix" | sort -V | tail -n 1)"
    if [[ "$newest" == "$left_suffix" ]]; then
        printf '1\n'
    else
        printf '%s\n' '-1'
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
        normalize-tag)
            shift
            normalize_release_tag "${1:-}"
            ;;
        assert-tracked)
            assert_tracked_contract
            ;;
        compare)
            compare_release_tags "${2:-}" "${3:-}"
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
