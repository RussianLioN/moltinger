#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SCRIPTS_VERIFY_SCRIPT="$PROJECT_ROOT/scripts/scripts-verify.sh"

setup_unit_scripts_verify() {
    require_commands_or_skip bash jq mktemp cat chmod cp rm sha256sum || return 2
    return 0
}

write_fixture_manifest() {
    local manifest_path="$1"
    local include_orphan="$2"
    local orphan_block=""

    if [[ "$include_orphan" == "true" ]]; then
        orphan_block=$',\n    "orphan.sh": {\n      "entrypoint": true\n    }'
    fi

    cat > "$manifest_path" <<EOF
{
  "scripts": {
    "scripts-verify.sh": {
      "entrypoint": true
    },
    "alpha.sh": {
      "entrypoint": true
    }$orphan_block
  },
  "dependencies": {
    "packages": {}
  }
}
EOF
}

run_unit_scripts_verify_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_unit_scripts_verify
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    test_start "unit_scripts_verify_fails_when_repo_contains_orphan_entrypoint"

    local fixture_root output_log
    fixture_root="$(secure_temp_dir scripts-verify)"
    output_log="$fixture_root/output.log"
    cp "$SCRIPTS_VERIFY_SCRIPT" "$fixture_root/scripts-verify.sh"
    chmod +x "$fixture_root/scripts-verify.sh"
    write_fixture_manifest "$fixture_root/manifest.json" "false"
    printf '#!/usr/bin/env bash\necho alpha\n' > "$fixture_root/alpha.sh"
    printf '#!/usr/bin/env bash\necho orphan\n' > "$fixture_root/orphan.sh"
    chmod +x "$fixture_root/alpha.sh" "$fixture_root/orphan.sh"

    if (cd "$fixture_root" && bash ./scripts-verify.sh >"$output_log" 2>&1); then
        test_fail "scripts-verify.sh must fail when an orphan script is present"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_contains "$(cat "$output_log")" "Orphan script not in manifest: orphan.sh" "scripts-verify.sh should report the orphan script explicitly"
    test_pass

    test_start "unit_scripts_verify_passes_when_manifest_covers_all_top_level_scripts"

    write_fixture_manifest "$fixture_root/manifest.json" "true"
    if ! (cd "$fixture_root" && bash ./scripts-verify.sh >"$output_log" 2>&1); then
        test_fail "scripts-verify.sh should pass once the orphan is added to the manifest"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_contains "$(cat "$output_log")" "All checks passed!" "scripts-verify.sh should report success after manifest alignment"
    rm -rf "$fixture_root"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_unit_scripts_verify_tests
fi
