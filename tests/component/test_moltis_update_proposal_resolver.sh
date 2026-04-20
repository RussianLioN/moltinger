#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

RESOLVER_SCRIPT="$PROJECT_ROOT/scripts/moltis-update-proposal-resolver.sh"

create_fake_docker_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "$fake_bin"
    cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "manifest" && "${2:-}" == "inspect" ]]; then
    requested_image="${3:-}"
    for allowed in ${FAKE_PULLABLE_IMAGES:-}; do
        if [[ "$requested_image" == "$allowed" ]]; then
            exit 0
        fi
    done
    exit 1
fi

printf 'unsupported fake docker command: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${fake_bin}/docker"
    printf '%s\n' "$fake_bin"
}

kv_value() {
    local key="$1"
    local payload="$2"

    awk -F= -v key="$key" '$1 == key { sub($1 FS, ""); print; exit }' <<<"$payload"
}

run_component_moltis_update_proposal_resolver_tests() {
    start_timer

    local fixture_root fake_bin
    fixture_root="$(mktemp -d /tmp/moltis-update-proposal-resolver.XXXXXX)"
    fake_bin="$(create_fake_docker_bin "$fixture_root")"

    test_start "component_moltis_update_proposal_resolver_accepts_calendar_release_tag_when_pullable"
    local calendar_output
    calendar_output="$(
        PATH="${fake_bin}:$PATH" \
        FAKE_PULLABLE_IMAGES="ghcr.io/moltis-org/moltis:20260420.02" \
        bash "$RESOLVER_SCRIPT" \
            --tracked-version "0.10.18" \
            --latest-release-tag "20260420.02"
    )"

    if [[ "$(kv_value should_update "$calendar_output")" == "true" ]] && \
       [[ "$(kv_value candidate_version "$calendar_output")" == "20260420.02" ]]; then
        test_pass
    else
        test_fail "Resolver should accept a pullable calendar-style GHCR release tag"
    fi

    test_start "component_moltis_update_proposal_resolver_skips_when_candidate_equals_tracked"
    local equal_output
    equal_output="$(
        PATH="${fake_bin}:$PATH" \
        FAKE_PULLABLE_IMAGES="ghcr.io/moltis-org/moltis:0.10.18" \
        bash "$RESOLVER_SCRIPT" \
            --tracked-version "0.10.18" \
            --latest-release-tag "v0.10.18"
    )"

    if [[ "$(kv_value should_update "$equal_output")" == "false" ]] && \
       [[ "$(kv_value skip_reason "$equal_output")" == "tracked version already equals latest release candidate" ]]; then
        test_pass
    else
        test_fail "Resolver should green-skip when upstream candidate already matches the tracked version"
    fi

    test_start "component_moltis_update_proposal_resolver_skips_when_candidate_not_pullable_yet"
    local unpullable_output
    unpullable_output="$(
        PATH="${fake_bin}:$PATH" \
        FAKE_PULLABLE_IMAGES="" \
        bash "$RESOLVER_SCRIPT" \
            --tracked-version "0.10.18" \
            --latest-release-tag "20260420.02"
    )"

    if [[ "$(kv_value should_update "$unpullable_output")" == "false" ]] && \
       [[ "$(kv_value skip_reason "$unpullable_output")" == "normalized GHCR tag ghcr.io/moltis-org/moltis:20260420.02 is not pullable yet" ]]; then
        test_pass
    else
        test_fail "Resolver should green-skip instead of failing when the normalized GHCR tag is not pullable yet"
    fi

    test_start "component_moltis_update_proposal_resolver_rejects_invalid_release_tag"
    if PATH="${fake_bin}:$PATH" \
        FAKE_PULLABLE_IMAGES="" \
        bash "$RESOLVER_SCRIPT" \
            --tracked-version "0.10.18" \
            --latest-release-tag "release/20260420" >/dev/null 2>&1; then
        test_fail "Resolver must fail closed when official release tag cannot normalize into an explicit GHCR runtime tag"
    else
        test_pass
    fi

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_update_proposal_resolver_tests
fi
