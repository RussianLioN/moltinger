#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_VERSION_HELPER="$PROJECT_ROOT/scripts/moltis-version.sh"

write_compose_fixture() {
    local path="$1"
    local image_line="$2"

    cat > "$path" <<EOF
services:
  moltis:
    image: ${image_line}
EOF
}

create_helper_fixture_project() {
    local root="$1"
    local project_dir="${root}/project"

    mkdir -p "${project_dir}/scripts"
    cp "$MOLTIS_VERSION_HELPER" "${project_dir}/scripts/moltis-version.sh"
    chmod +x "${project_dir}/scripts/moltis-version.sh"
    printf '%s\n' "${project_dir}"
}

run_component_moltis_version_helper_tests() {
    start_timer

    local fixture_root project_dir helper_copy
    fixture_root="$(mktemp -d /tmp/moltis-version-helper.XXXXXX)"
    project_dir="$(create_helper_fixture_project "$fixture_root")"
    helper_copy="${project_dir}/scripts/moltis-version.sh"

    test_start "component_moltis_version_helper_rejects_latest_default"
    local latest_main latest_prod
    latest_main="${project_dir}/docker-compose.yml"
    latest_prod="${project_dir}/docker-compose.prod.yml"
    write_compose_fixture "$latest_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}'
    write_compose_fixture "$latest_prod" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}'

    if "$helper_copy" version >/dev/null 2>&1; then
        test_fail "Helper must reject latest as the tracked Moltis version"
    else
        test_pass
    fi

    test_start "component_moltis_version_helper_release_tag_default"
    local tagged_main tagged_prod tagged_version tagged_image
    tagged_main="${project_dir}/docker-compose.yml"
    tagged_prod="${project_dir}/docker-compose.prod.yml"
    write_compose_fixture "$tagged_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-0.10.18}'
    write_compose_fixture "$tagged_prod" 'ghcr.io/moltis-org/moltis:0.10.18'

    tagged_version="$("$helper_copy" version)"
    tagged_image="$("$helper_copy" image)"

    if [[ "$tagged_version" == "0.10.18" ]] && \
       [[ "$tagged_image" == "ghcr.io/moltis-org/moltis:0.10.18" ]] && \
       "$helper_copy" assert-tracked >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Helper should normalize and validate a pinned release-tag contract from compose files"
    fi

    test_start "component_moltis_version_helper_supports_quoted_comment_default_syntax"
    local quoted_main quoted_prod quoted_version quoted_image
    quoted_main="${project_dir}/docker-compose.yml"
    quoted_prod="${project_dir}/docker-compose.prod.yml"
    write_compose_fixture "$quoted_main" '"ghcr.io/moltis-org/moltis:${MOLTIS_VERSION-0.10.18}" # pinned via default'
    write_compose_fixture "$quoted_prod" "'ghcr.io/moltis-org/moltis:0.10.18' # explicit prod image"

    quoted_version="$("$helper_copy" version)"
    quoted_image="$("$helper_copy" image)"

    if [[ "$quoted_version" == "0.10.18" ]] && \
       [[ "$quoted_image" == "ghcr.io/moltis-org/moltis:0.10.18" ]]; then
        test_pass
    else
        test_fail "Helper should normalize quoted compose image lines, comments, and ${MOLTIS_VERSION-...} defaults"
    fi

    test_start "component_moltis_version_helper_rejects_non_defaulted_variable"
    local variable_main variable_prod
    variable_main="${project_dir}/docker-compose.yml"
    variable_prod="${project_dir}/docker-compose.prod.yml"
    write_compose_fixture "$variable_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION}'
    write_compose_fixture "$variable_prod" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION}'

    if "$helper_copy" version >/dev/null 2>&1; then
        test_fail "Helper must reject non-defaulted MOLTIS_VERSION expressions"
    else
        test_pass
    fi

    test_start "component_moltis_version_helper_rejects_compose_mismatch"
    local mismatch_main mismatch_prod
    mismatch_main="${project_dir}/docker-compose.yml"
    mismatch_prod="${project_dir}/docker-compose.prod.yml"
    write_compose_fixture "$mismatch_main" 'ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}'
    write_compose_fixture "$mismatch_prod" 'ghcr.io/moltis-org/moltis:0.10.18'

    if "$helper_copy" version >/dev/null 2>&1; then
        test_fail "Helper must fail when dev/prod compose contracts disagree"
    else
        test_pass
    fi

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_version_helper_tests
fi
