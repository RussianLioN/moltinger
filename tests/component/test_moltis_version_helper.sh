#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_VERSION_HELPER="$PROJECT_ROOT/scripts/moltis-version.sh"

write_compose_fixture() {
    local path="$1"
    local image_ref="$2"

    cat > "$path" <<EOF
services:
  moltis:
    image: ${image_ref}
EOF
}

run_component_moltis_version_helper_tests() {
    start_timer

    local fixture_root
    fixture_root="$(mktemp -d /tmp/moltis-version-helper.XXXXXX)"

    test_start "component_moltis_version_helper_latest_default"
    local latest_main latest_prod latest_version latest_image latest_policy
    latest_main="${fixture_root}/docker-compose.yml"
    latest_prod="${fixture_root}/docker-compose.prod.yml"
    write_compose_fixture "$latest_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}'
    write_compose_fixture "$latest_prod" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}'

    latest_version="$(COMPOSE_MAIN="$latest_main" COMPOSE_PROD="$latest_prod" "$MOLTIS_VERSION_HELPER" version)"
    latest_image="$(COMPOSE_MAIN="$latest_main" COMPOSE_PROD="$latest_prod" "$MOLTIS_VERSION_HELPER" image)"
    latest_policy="$(COMPOSE_MAIN="$latest_main" COMPOSE_PROD="$latest_prod" "$MOLTIS_VERSION_HELPER" policy)"

    if [[ "$latest_version" == "latest" ]] && \
       [[ "$latest_image" == "ghcr.io/moltis-org/moltis:latest" ]] && \
       [[ "$latest_policy" == "latest" ]]; then
        test_pass
    else
        rm -rf "$fixture_root"
        test_fail "Helper should resolve tracked latest contract from matching compose defaults"
    fi

    test_start "component_moltis_version_helper_release_tag_default"
    local tagged_main tagged_prod tagged_version tagged_image tagged_policy
    tagged_main="${fixture_root}/docker-compose-tagged.yml"
    tagged_prod="${fixture_root}/docker-compose-tagged.prod.yml"
    write_compose_fixture "$tagged_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-v0.10.18}'
    write_compose_fixture "$tagged_prod" 'ghcr.io/moltis-org/moltis:v0.10.18'

    tagged_version="$(COMPOSE_MAIN="$tagged_main" COMPOSE_PROD="$tagged_prod" "$MOLTIS_VERSION_HELPER" version)"
    tagged_image="$(COMPOSE_MAIN="$tagged_main" COMPOSE_PROD="$tagged_prod" "$MOLTIS_VERSION_HELPER" image)"
    tagged_policy="$(COMPOSE_MAIN="$tagged_main" COMPOSE_PROD="$tagged_prod" "$MOLTIS_VERSION_HELPER" policy)"

    if [[ "$tagged_version" == "v0.10.18" ]] && \
       [[ "$tagged_image" == "ghcr.io/moltis-org/moltis:v0.10.18" ]] && \
       [[ "$tagged_policy" == "release-tag" ]]; then
        test_pass
    else
        rm -rf "$fixture_root"
        test_fail "Helper should normalize an explicit release tag contract from compose files"
    fi

    test_start "component_moltis_version_helper_rejects_compose_mismatch"
    local mismatch_main mismatch_prod
    mismatch_main="${fixture_root}/docker-compose-mismatch.yml"
    mismatch_prod="${fixture_root}/docker-compose-mismatch.prod.yml"
    write_compose_fixture "$mismatch_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}'
    write_compose_fixture "$mismatch_prod" 'ghcr.io/moltis-org/moltis:v0.10.18'

    if COMPOSE_MAIN="$mismatch_main" COMPOSE_PROD="$mismatch_prod" "$MOLTIS_VERSION_HELPER" version >/dev/null 2>&1; then
        rm -rf "$fixture_root"
        test_fail "Helper must fail when dev/prod compose contracts disagree"
    else
        rm -rf "$fixture_root"
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_version_helper_tests
fi
