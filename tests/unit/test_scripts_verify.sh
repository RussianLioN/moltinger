#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SCRIPTS_VERIFY_SCRIPT="$PROJECT_ROOT/scripts/scripts-verify.sh"

setup_unit_scripts_verify() {
    require_commands_or_skip bash jq mktemp cat chmod cp rm sha256sum cmp || return 2
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

write_fixture_hashes() {
    local fixture_root="$1"
    local hashes_file="$fixture_root/.scripts-hashes"

    : > "$hashes_file"
    for script in "$fixture_root"/*.sh; do
        local basename hash
        basename=$(basename "$script")
        hash=$(sha256sum "$script" | awk '{print $1}')
        printf '%s:%s\n' "$basename" "$hash" >> "$hashes_file"
    done

    sort -o "$hashes_file" "$hashes_file"
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

    test_start "unit_scripts_verify_requires_explicit_hash_refresh_and_stays_read_only_by_default"

    write_fixture_manifest "$fixture_root/manifest.json" "true"
    rm -f "$fixture_root/.scripts-hashes"

    if (cd "$fixture_root" && bash ./scripts-verify.sh >"$output_log" 2>&1); then
        test_fail "scripts-verify.sh must fail when the hash baseline is missing"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_contains "$(cat "$output_log")" "Hash baseline missing" "scripts-verify.sh should fail closed without a tracked hash baseline"

    if ! (cd "$fixture_root" && bash ./scripts-verify.sh --refresh-hashes >"$output_log" 2>&1); then
        test_fail "scripts-verify.sh --refresh-hashes should create the baseline explicitly"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_file_exists "$fixture_root/.scripts-hashes" "scripts-verify.sh --refresh-hashes should create the baseline file"
    cp "$fixture_root/.scripts-hashes" "$fixture_root/.scripts-hashes.before"

    if ! (cd "$fixture_root" && bash ./scripts-verify.sh >"$output_log" 2>&1); then
        test_fail "scripts-verify.sh should pass once manifest and baseline are aligned"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    cmp -s "$fixture_root/.scripts-hashes" "$fixture_root/.scripts-hashes.before" || {
        test_fail "scripts-verify.sh should not rewrite the hash baseline during a read-only verify run"
        rm -rf "$fixture_root"
        generate_report
        return
    }

    test_pass

    test_start "unit_scripts_verify_fails_on_hash_drift_without_rewriting_baseline"

    printf '#!/usr/bin/env bash\necho alpha changed\n' > "$fixture_root/alpha.sh"
    chmod +x "$fixture_root/alpha.sh"

    if (cd "$fixture_root" && bash ./scripts-verify.sh >"$output_log" 2>&1); then
        test_fail "scripts-verify.sh must fail when a tracked script drifts from the baseline"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_contains "$(cat "$output_log")" "CHANGED: alpha.sh" "scripts-verify.sh should report hash drift explicitly"
    cmp -s "$fixture_root/.scripts-hashes" "$fixture_root/.scripts-hashes.before" || {
        test_fail "scripts-verify.sh must not rewrite the baseline when drift is detected"
        rm -rf "$fixture_root"
        generate_report
        return
    }

    rm -rf "$fixture_root"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_unit_scripts_verify_tests
fi
