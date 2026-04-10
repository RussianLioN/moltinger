#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

PREPARE_SCRIPT="$PROJECT_ROOT/scripts/prepare-moltis-runtime-config.sh"

run_component_prepare_moltis_runtime_config_tests() {
    start_timer

    test_start "component_prepare_runtime_config_preserves_auth_files_and_normalizes_openai_codex_model_order"

    local fixture_root static_dir runtime_dir
    fixture_root="$(secure_temp_dir prepare-moltis-runtime-config)"
    static_dir="$fixture_root/static"
    runtime_dir="$fixture_root/runtime"

    mkdir -p "$static_dir/subdir" "$runtime_dir"
    cat >"$static_dir/moltis.toml" <<'EOF'
[providers.openai-codex]
enabled = true
model = "gpt-5.4"
models = ["gpt-5.4"]
EOF
    printf 'tracked\n' >"$static_dir/subdir/marker.txt"

    cat >"$runtime_dir/oauth_tokens.json" <<'EOF'
{"openai-codex":{"refresh_token":"refresh-token"}}
EOF
    cat >"$runtime_dir/provider_keys.json" <<'EOF'
{
  "openai-codex": {
    "models": ["gpt-5.4-mini", "gpt-5.4", "gpt-5.3-codex"]
  },
  "zai": {
    "models": ["glm-5"]
  }
}
EOF

    if ! bash "$PREPARE_SCRIPT" "$static_dir" "$runtime_dir" >"$fixture_root/stdout.log" 2>"$fixture_root/stderr.log"; then
        test_fail "prepare-moltis-runtime-config.sh should succeed for a valid static/runtime fixture"
        rm -rf "$fixture_root"
        return
    fi

    assert_file_exists "$runtime_dir/moltis.toml" "Runtime moltis.toml should be copied from static config"
    assert_file_exists "$runtime_dir/subdir/marker.txt" "Static directories should be copied into runtime config"
    assert_contains "$(cat "$runtime_dir/oauth_tokens.json")" '"refresh_token":"refresh-token"' "oauth_tokens.json must stay preserved"

    if [[ "$(jq -r '."openai-codex".models[0]' "$runtime_dir/provider_keys.json")" != "gpt-5.4" ]] || \
       [[ "$(jq -r '."openai-codex".models[1]' "$runtime_dir/provider_keys.json")" != "gpt-5.4-mini" ]] || \
       [[ "$(jq -r '.zai.models[0]' "$runtime_dir/provider_keys.json")" != "glm-5" ]]; then
        test_fail "prepare-moltis-runtime-config.sh must keep tracked gpt-5.4 first while preserving the rest of provider_keys.json"
        rm -rf "$fixture_root"
        return
    fi

    rm -rf "$fixture_root"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_prepare_moltis_runtime_config_tests
fi
