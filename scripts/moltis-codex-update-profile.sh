#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_SCHEMA_PATH="${PROJECT_ROOT}/specs/023-full-moltis-codex-update-skill/contracts/project-profile.schema.json"

COMMAND="${1:-}"
PROFILE_FILE=""
SCHEMA_PATH="${MOLTIS_CODEX_UPDATE_PROFILE_SCHEMA:-${DEFAULT_SCHEMA_PATH}}"
JSON_OUTPUT=true

usage() {
    cat <<'EOF'
Usage:
  moltis-codex-update-profile.sh <command> [options]

Commands:
  validate        Validate one optional project profile against the stable contract
  load            Validate and print a normalized profile payload

Options:
  --file PATH     Path to the project profile JSON
  --schema PATH   Path to the profile schema JSON
  --json          Print JSON output (default)
  -h, --help      Show help
EOF
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

parse_args() {
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                PROFILE_FILE="${2:?missing value for --file}"
                shift 2
                ;;
            --schema)
                SCHEMA_PATH="${2:?missing value for --schema}"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown argument: $1"
                ;;
        esac
    done
}

run_validator() {
    python3 - "$COMMAND" "$PROFILE_FILE" "$SCHEMA_PATH" <<'PY'
import json
import pathlib
import sys

command, profile_path_raw, schema_path_raw = sys.argv[1:4]
profile_path = pathlib.Path(profile_path_raw) if profile_path_raw else None
schema_path = pathlib.Path(schema_path_raw)

result = {
    "ok": False,
    "command": command,
    "schema_path": str(schema_path),
    "profile_path": str(profile_path) if profile_path else "",
    "errors": [],
}

if not schema_path.is_file():
    result["errors"].append(f"Schema file not found: {schema_path}")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1)

if profile_path is None or not profile_path_raw:
    result["errors"].append("Profile file is required")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1)

if not profile_path.is_file():
    result["errors"].append(f"Profile file not found: {profile_path}")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1)

try:
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
except Exception as exc:
    result["errors"].append(f"Failed to parse profile JSON: {exc}")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1)

errors = []
if not isinstance(profile, dict):
    errors.append("Profile must be a JSON object")
else:
    if profile.get("schema_version") != "codex-update-project-profile/v1":
        errors.append("schema_version must be codex-update-project-profile/v1")
    if not isinstance(profile.get("profile_id"), str) or not profile.get("profile_id", "").strip():
        errors.append("profile_id must be a non-empty string")
    if not isinstance(profile.get("project_name"), str) or not profile.get("project_name", "").strip():
        errors.append("project_name must be a non-empty string")
    traits = profile.get("traits")
    if not isinstance(traits, list) or any(not isinstance(item, str) or not item.strip() for item in traits):
        errors.append("traits must be an array of non-empty strings")

    template_ids = set()
    recommendation_templates = profile.get("recommendation_templates", [])
    if recommendation_templates is not None:
        if not isinstance(recommendation_templates, list):
            errors.append("recommendation_templates must be an array when provided")
            recommendation_templates = []
        else:
            for index, template in enumerate(recommendation_templates, start=1):
                if not isinstance(template, dict):
                    errors.append(f"recommendation_templates[{index}] must be an object")
                    continue
                template_id = template.get("id", "")
                if not isinstance(template_id, str) or not template_id.strip():
                    errors.append(f"recommendation_templates[{index}].id must be a non-empty string")
                elif template_id.strip() in template_ids:
                    errors.append(f"recommendation_templates[{index}].id must be unique")
                else:
                    template_ids.add(template_id.strip())
                if not isinstance(template.get("title_ru"), str) or not template.get("title_ru", "").strip():
                    errors.append(f"recommendation_templates[{index}].title_ru must be a non-empty string")
                if not isinstance(template.get("rationale_ru"), str) or not template.get("rationale_ru", "").strip():
                    errors.append(f"recommendation_templates[{index}].rationale_ru must be a non-empty string")
                next_steps = template.get("next_steps_ru")
                if not isinstance(next_steps, list) or not next_steps or any(not isinstance(item, str) or not item.strip() for item in next_steps):
                    errors.append(f"recommendation_templates[{index}].next_steps_ru must be a non-empty array of non-empty strings")
                if "impacted_paths" in template:
                    impacted_paths = template.get("impacted_paths")
                    if not isinstance(impacted_paths, list) or any(not isinstance(item, str) or not item.strip() for item in impacted_paths):
                        errors.append(f"recommendation_templates[{index}].impacted_paths must be an array of non-empty strings")

    rules = profile.get("relevance_rules")
    if not isinstance(rules, list) or not rules:
        errors.append("relevance_rules must be a non-empty array")
    else:
        rule_ids = set()
        for index, rule in enumerate(rules, start=1):
            if not isinstance(rule, dict):
                errors.append(f"relevance_rules[{index}] must be an object")
                continue
            rule_id = rule.get("id", "")
            if not isinstance(rule_id, str) or not rule_id.strip():
                errors.append(f"relevance_rules[{index}].id must be a non-empty string")
            elif rule_id.strip() in rule_ids:
                errors.append(f"relevance_rules[{index}].id must be unique")
            else:
                rule_ids.add(rule_id.strip())
            keywords = rule.get("keywords")
            if not isinstance(keywords, list) or any(not isinstance(item, str) or not item.strip() for item in keywords):
                errors.append(f"relevance_rules[{index}].keywords must be an array of non-empty strings")
            if not isinstance(rule.get("title_ru"), str) or not rule.get("title_ru", "").strip():
                errors.append(f"relevance_rules[{index}].title_ru must be a non-empty string")
            if not isinstance(rule.get("rationale_ru"), str) or not rule.get("rationale_ru", "").strip():
                errors.append(f"relevance_rules[{index}].rationale_ru must be a non-empty string")
            next_steps = rule.get("next_steps_ru")
            if not isinstance(next_steps, list) or not next_steps or any(not isinstance(item, str) or not item.strip() for item in next_steps):
                errors.append(f"relevance_rules[{index}].next_steps_ru must be a non-empty array of non-empty strings")
            if "priority_paths" in rule:
                priority_paths = rule.get("priority_paths")
                if not isinstance(priority_paths, list) or any(not isinstance(item, str) or not item.strip() for item in priority_paths):
                    errors.append(f"relevance_rules[{index}].priority_paths must be an array of non-empty strings")
            if "recommendation_template_id" in rule:
                template_id = rule.get("recommendation_template_id")
                if not isinstance(template_id, str) or not template_id.strip():
                    errors.append(f"relevance_rules[{index}].recommendation_template_id must be a non-empty string")
                elif template_id.strip() not in template_ids:
                    errors.append(f"relevance_rules[{index}].recommendation_template_id must reference an existing template id")

    fallback = profile.get("fallback_recommendation")
    if fallback is not None:
        if not isinstance(fallback, dict):
            errors.append("fallback_recommendation must be an object when provided")
        else:
            if not isinstance(fallback.get("title_ru"), str) or not fallback.get("title_ru", "").strip():
                errors.append("fallback_recommendation.title_ru must be a non-empty string")
            if not isinstance(fallback.get("rationale_ru"), str) or not fallback.get("rationale_ru", "").strip():
                errors.append("fallback_recommendation.rationale_ru must be a non-empty string")
            next_steps = fallback.get("next_steps_ru")
            if not isinstance(next_steps, list) or not next_steps or any(not isinstance(item, str) or not item.strip() for item in next_steps):
                errors.append("fallback_recommendation.next_steps_ru must be a non-empty array of non-empty strings")
            if "impacted_paths" in fallback:
                impacted_paths = fallback.get("impacted_paths")
                if not isinstance(impacted_paths, list) or any(not isinstance(item, str) or not item.strip() for item in impacted_paths):
                    errors.append("fallback_recommendation.impacted_paths must be an array of non-empty strings")

result["errors"] = errors
if errors:
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1)

normalized = {
    "schema_version": "codex-update-project-profile/v1",
    "profile_id": profile["profile_id"].strip(),
    "project_name": profile["project_name"].strip(),
    "owner": str(profile.get("owner", "")).strip(),
    "traits": [item.strip() for item in profile.get("traits", []) if isinstance(item, str) and item.strip()],
    "relevance_rules": [],
    "recommendation_templates": [],
    "fallback_recommendation": None,
}

for rule in profile.get("relevance_rules", []):
    normalized["relevance_rules"].append(
        {
            "id": rule["id"].strip(),
            "keywords": [item.strip() for item in rule.get("keywords", []) if isinstance(item, str) and item.strip()],
            "title_ru": rule["title_ru"].strip(),
            "rationale_ru": rule["rationale_ru"].strip(),
            "next_steps_ru": [item.strip() for item in rule.get("next_steps_ru", []) if isinstance(item, str) and item.strip()],
            "priority_paths": [item.strip() for item in rule.get("priority_paths", []) if isinstance(item, str) and item.strip()],
            "recommendation_template_id": str(rule.get("recommendation_template_id", "")).strip(),
        }
    )

for template in profile.get("recommendation_templates", []):
    normalized["recommendation_templates"].append(
        {
            "id": template["id"].strip(),
            "title_ru": template["title_ru"].strip(),
            "rationale_ru": template["rationale_ru"].strip(),
            "next_steps_ru": [item.strip() for item in template.get("next_steps_ru", []) if isinstance(item, str) and item.strip()],
            "impacted_paths": [item.strip() for item in template.get("impacted_paths", []) if isinstance(item, str) and item.strip()],
        }
    )

if isinstance(profile.get("fallback_recommendation"), dict):
    fallback = profile["fallback_recommendation"]
    normalized["fallback_recommendation"] = {
        "title_ru": fallback["title_ru"].strip(),
        "rationale_ru": fallback["rationale_ru"].strip(),
        "next_steps_ru": [item.strip() for item in fallback.get("next_steps_ru", []) if isinstance(item, str) and item.strip()],
        "impacted_paths": [item.strip() for item in fallback.get("impacted_paths", []) if isinstance(item, str) and item.strip()],
    }

result["ok"] = True
result["profile_id"] = normalized["profile_id"]
result["project_name"] = normalized["project_name"]
result["traits"] = normalized["traits"]
result["profile"] = normalized
print(json.dumps(result, ensure_ascii=False))
PY
}

main() {
    parse_args "$@"
    case "$COMMAND" in
        validate|load) ;;
        ""|-h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown command: $COMMAND"
            ;;
    esac

    local output status=0
    set +e
    output="$(run_validator)"
    status=$?
    set -e

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        printf '%s\n' "$output"
    fi
    return "$status"
}

main "$@"
