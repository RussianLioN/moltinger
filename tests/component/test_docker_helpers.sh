#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

run_component_docker_helper_tests() {
    start_timer

    test_start "component_docker_helper_parses_ndjson_ps_output"
    local ndjson_status
    ndjson_status=$(cat <<'JSON' | compose_service_health_from_ps_json "moltis"
{"Service":"ollama","Health":"healthy"}
{"Service":"moltis","Health":"healthy"}
{"Service":"test-runner","Health":""}
JSON
)
    assert_eq "healthy" "$ndjson_status" "Docker helper should parse Compose v5 NDJSON ps output"
    test_pass

    test_start "component_docker_helper_parses_array_ps_output"
    local array_status
    array_status=$(cat <<'JSON' | compose_service_health_from_ps_json "moltis"
[
  {"Service":"ollama","Health":"healthy"},
  {"Service":"moltis","Health":"healthy"},
  {"Service":"test-runner","Health":""}
]
JSON
)
    assert_eq "healthy" "$array_status" "Docker helper should parse array-form ps output"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_docker_helper_tests
fi
