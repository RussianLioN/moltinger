#!/usr/bin/env bash
# Upsert a sticky GitHub issue/PR comment identified by a marker string.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  upsert_sticky_comment.sh \
    --repo <owner/name> \
    --issue-number <number> \
    --marker <marker-string> \
    --body-file <path>

Environment:
  GH_TOKEN   Required GitHub token with issues/pull-requests write access.
USAGE
}

REPO=""
ISSUE_NUMBER=""
MARKER=""
BODY_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="$2"
            shift 2
            ;;
        --issue-number)
            ISSUE_NUMBER="$2"
            shift 2
            ;;
        --marker)
            MARKER="$2"
            shift 2
            ;;
        --body-file)
            BODY_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$REPO" || -z "$ISSUE_NUMBER" || -z "$MARKER" || -z "$BODY_FILE" ]]; then
    echo "ERROR: --repo, --issue-number, --marker and --body-file are required." >&2
    usage
    exit 2
fi

if [[ ! -f "$BODY_FILE" ]]; then
    echo "ERROR: Body file not found: $BODY_FILE" >&2
    exit 2
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "ERROR: GH_TOKEN is required." >&2
    exit 3
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh command not found." >&2
    exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq command not found." >&2
    exit 4
fi

body_json="$(mktemp)"
cleanup() {
    rm -f "$body_json"
}
trap cleanup EXIT

jq -n --rawfile body "$BODY_FILE" '{body: $body}' > "$body_json"

existing_id="$(
    gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments?per_page=100" --paginate 2>/dev/null \
        | jq -r --arg marker "$MARKER" '.[] | select((.body // "") | contains($marker)) | .id' \
        | tail -n 1 || true
)"

if [[ -n "$existing_id" ]]; then
    response="$(gh api "repos/$REPO/issues/comments/$existing_id" -X PATCH --input "$body_json")"
    comment_id="$(echo "$response" | jq -r '.id // empty')"
    echo "mode=updated"
    echo "comment_id=$comment_id"
else
    response="$(gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" -X POST --input "$body_json")"
    comment_id="$(echo "$response" | jq -r '.id // empty')"
    echo "mode=created"
    echo "comment_id=$comment_id"
fi
