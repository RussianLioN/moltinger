#!/bin/bash
# Prepare a writable Moltis runtime config directory outside the git-synced tree.
# Static config is copied from the repo-managed config/ directory.
# Auth/state files stay in the runtime directory and are never overwritten here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

STATIC_CONFIG_DIR="${1:-${MOLTIS_STATIC_CONFIG_DIR:-$PROJECT_ROOT/config}}"
RUNTIME_CONFIG_DIR="${2:-${MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}}"
SERVICE_UID="${MOLTIS_SERVICE_UID:-1000}"
SERVICE_GID="${MOLTIS_SERVICE_GID:-1000}"

log() {
    echo "[prepare-moltis-runtime-config] $*"
}

read_toml_key() {
    local toml_file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$toml_file" ]] || return 1

    awk -v section="$section" -v key="$key" '
        BEGIN { in_section = 0 }
        /^[[:space:]]*\[/ {
            in_section = ($0 == section)
            next
        }
        in_section && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*#.*$/, "", line)
            sub("^[^=]+=[[:space:]]*", "", line)
            gsub(/^"/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$toml_file"
}

copy_static_item() {
    local src="$1"
    local dst="$2"

    if [[ -d "$src" ]]; then
        mkdir -p "$dst"
        cp -R "$src/." "$dst/"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    fi
}

normalize_openai_codex_model_preferences() {
    local tracked_model provider_keys_file tmp_file

    tracked_model="$(read_toml_key "$STATIC_CONFIG_DIR/moltis.toml" "[providers.openai-codex]" "model" || true)"
    provider_keys_file="$RUNTIME_CONFIG_DIR/provider_keys.json"

    [[ -n "$tracked_model" ]] || return 0
    [[ -f "$provider_keys_file" ]] || return 0

    if ! command -v jq >/dev/null 2>&1; then
        log "jq is unavailable, skipping runtime model preference normalization"
        return 0
    fi

    if ! jq -e '.["openai-codex"]? | type == "object"' "$provider_keys_file" >/dev/null 2>&1; then
        return 0
    fi

    tmp_file="$provider_keys_file.tmp.$$"
    if ! jq \
        --arg tracked_model "$tracked_model" \
        '
        .["openai-codex"].models = (
          [$tracked_model] +
          (
            (.["openai-codex"].models // [])
            | if type == "array" then map(select(. != $tracked_model)) else [] end
          )
        )
        ' "$provider_keys_file" >"$tmp_file"; then
        rm -f "$tmp_file"
        echo "Failed to normalize OpenAI Codex model preferences in $provider_keys_file" >&2
        exit 1
    fi

    mv "$tmp_file" "$provider_keys_file"
    log "normalized runtime-managed openai-codex preferences to keep $tracked_model primary"
}

normalize_glm_provider_preferences() {
    local tracked_model provider_alias provider_keys_file tmp_file

    tracked_model="$(read_toml_key "$STATIC_CONFIG_DIR/moltis.toml" "[providers.openai]" "model" || true)"
    provider_alias="$(read_toml_key "$STATIC_CONFIG_DIR/moltis.toml" "[providers.openai]" "alias" || true)"
    provider_keys_file="$RUNTIME_CONFIG_DIR/provider_keys.json"

    [[ -n "$tracked_model" && -n "$provider_alias" ]] || return 0
    [[ -f "$provider_keys_file" ]] || return 0

    if ! command -v jq >/dev/null 2>&1; then
        log "jq is unavailable, skipping GLM runtime preference normalization"
        return 0
    fi

    tmp_file="$provider_keys_file.tmp.$$"
    if ! jq \
        --arg provider_alias "$provider_alias" \
        --arg tracked_model "$tracked_model" \
        '
        . as $root
        | ($root[$provider_alias] // $root["zai"] // {}) as $preferred_entry
        | ($root["zai"] // {}) as $legacy_zai
        | ($root["zai-telegram-safe"] // {}) as $legacy_safe_alias
        | ($root["custom-zai-telegram-safe"] // {}) as $legacy_custom_safe
        | .[$provider_alias] = (
            (if ($preferred_entry | type) == "object" then $preferred_entry else {} end)
            | .models = (
                [$tracked_model] +
                (
                    (
                        (
                            (($preferred_entry.models // []) | if type == "array" then . else [] end) +
                            (($legacy_zai.models // []) | if type == "array" then . else [] end) +
                            (($legacy_safe_alias.models // []) | if type == "array" then . else [] end) +
                            (($legacy_custom_safe.models // []) | if type == "array" then . else [] end)
                        )
                        | map(select(. != $tracked_model))
                    )
                    | unique
                )
            )
        )
        | del(.["zai"], .["zai-telegram-safe"], .["custom-zai-telegram-safe"])
        ' "$provider_keys_file" >"$tmp_file"; then
        rm -f "$tmp_file"
        echo "Failed to normalize GLM provider preferences in $provider_keys_file" >&2
        exit 1
    fi

    mv "$tmp_file" "$provider_keys_file"
    log "normalized runtime-managed $provider_alias preferences and removed legacy runtime GLM aliases"
}

main() {
    if [[ ! -d "$STATIC_CONFIG_DIR" ]]; then
        echo "Static config directory not found: $STATIC_CONFIG_DIR" >&2
        exit 1
    fi

    mkdir -p "$RUNTIME_CONFIG_DIR"
    chmod 700 "$RUNTIME_CONFIG_DIR" 2>/dev/null || true

    for src in "$STATIC_CONFIG_DIR"/*; do
        [[ -e "$src" ]] || continue
        name="$(basename "$src")"

        case "$name" in
            oauth_tokens.json|provider_keys.json|credentials.json)
                log "preserving runtime-managed auth file: $name"
                continue
                ;;
        esac

        copy_static_item "$src" "$RUNTIME_CONFIG_DIR/$name"
    done

    if [[ "$(id -u)" -eq 0 ]]; then
        chown -R "$SERVICE_UID:$SERVICE_GID" "$RUNTIME_CONFIG_DIR"
    fi

    for runtime_file in oauth_tokens.json provider_keys.json credentials.json; do
        if [[ -f "$RUNTIME_CONFIG_DIR/$runtime_file" ]]; then
            chmod 600 "$RUNTIME_CONFIG_DIR/$runtime_file" 2>/dev/null || true
            if [[ "$(id -u)" -eq 0 ]]; then
                chown "$SERVICE_UID:$SERVICE_GID" "$RUNTIME_CONFIG_DIR/$runtime_file"
            fi
        fi
    done

    normalize_openai_codex_model_preferences
    normalize_glm_provider_preferences

    if [[ -f "$RUNTIME_CONFIG_DIR/provider_keys.json" ]]; then
        chmod 600 "$RUNTIME_CONFIG_DIR/provider_keys.json" 2>/dev/null || true
        if [[ "$(id -u)" -eq 0 ]]; then
            chown "$SERVICE_UID:$SERVICE_GID" "$RUNTIME_CONFIG_DIR/provider_keys.json"
        fi
    fi

    log "runtime config prepared at $RUNTIME_CONFIG_DIR"
}

main "$@"
