#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/moltis-update-proposal-workflow.sh prepare-branch --candidate-version <version>
  scripts/moltis-update-proposal-workflow.sh sync-pr \
    --candidate-version <version> \
    --tracked-version <version> \
    --latest-release-tag <tag> \
    --branch <branch>
EOF
}

append_output() {
    local key="$1"
    local value="$2"

    [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
}

prepare_branch() {
    local candidate_version=""
    local branch rendered_version

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --candidate-version)
                candidate_version="${2:-}"
                shift 2
                ;;
            *)
                echo "moltis-update-proposal-workflow.sh: unknown argument for prepare-branch: $1" >&2
                exit 1
                ;;
        esac
    done

    [[ -n "$candidate_version" ]] || {
        echo "moltis-update-proposal-workflow.sh: --candidate-version is required" >&2
        exit 1
    }

    branch="chore/moltis-update-${candidate_version}"

    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git switch -C "$branch"

    for compose_file in docker-compose.yml docker-compose.prod.yml; do
        perl -0pi -e "s#(ghcr\\.io/moltis-org/moltis:\\$\\{MOLTIS_VERSION:-)[^}]+(\\})#\${1}${candidate_version}\${2}#g" "$compose_file"
    done

    bash ./scripts/moltis-version.sh assert-tracked
    rendered_version="$(bash ./scripts/moltis-version.sh version)"
    if [[ "$rendered_version" != "$candidate_version" ]]; then
        echo "::error::Version render mismatch after update. expected=$candidate_version actual=$rendered_version"
        exit 1
    fi

    if git diff --quiet -- docker-compose.yml docker-compose.prod.yml; then
        append_output "has_changes" "false"
        append_output "branch" "$branch"
        return 0
    fi

    git add docker-compose.yml docker-compose.prod.yml
    git commit -m "chore(moltis): propose update to $candidate_version"
    git push --force-with-lease origin "$branch"

    append_output "has_changes" "true"
    append_output "branch" "$branch"
}

sync_pr() {
    local candidate_version=""
    local tracked_version=""
    local latest_release_tag=""
    local branch=""
    local body_file existing_pr_number pr_url create_output create_rc pr_mode

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --candidate-version)
                candidate_version="${2:-}"
                shift 2
                ;;
            --tracked-version)
                tracked_version="${2:-}"
                shift 2
                ;;
            --latest-release-tag)
                latest_release_tag="${2:-}"
                shift 2
                ;;
            --branch)
                branch="${2:-}"
                shift 2
                ;;
            *)
                echo "moltis-update-proposal-workflow.sh: unknown argument for sync-pr: $1" >&2
                exit 1
                ;;
        esac
    done

    [[ -n "$candidate_version" && -n "$tracked_version" && -n "$latest_release_tag" && -n "$branch" ]] || {
        echo "moltis-update-proposal-workflow.sh: --candidate-version, --tracked-version, --latest-release-tag, and --branch are required" >&2
        exit 1
    }

    body_file="$(mktemp)"

    cat > "$body_file" <<EOF
## Automated Moltis update proposal

- Current tracked version: \`${tracked_version}\`
- Upstream latest release: \`${latest_release_tag}\`
- Candidate GHCR runtime tag: \`${candidate_version}\`

## Safety checks already passed

- upstream release discovered from official \`moltis-org/moltis\`
- release tag normalized and validated against explicit GHCR runtime tag rules
- \`ghcr.io/moltis-org/moltis:${candidate_version}\` is pullable
- compose tracked defaults updated consistently

## Approval flow

1. Review this PR.
2. Approve and merge when ready.
3. Standard production deploy from \`main\` will apply the update with existing backup-safe gates.
EOF

    existing_pr_number="$(gh pr list --base main --head "$branch" --state open --json number --jq '.[0].number // empty')"
    pr_mode="unknown"

    if [[ -n "$existing_pr_number" ]]; then
        pr_url="$(gh pr view "$existing_pr_number" --json url --jq '.url')"
        if gh pr edit "$existing_pr_number" --title "chore(moltis): propose update to ${candidate_version}" --body-file "$body_file"; then
            pr_mode="existing_pr_updated"
        else
            pr_mode="existing_pr_unmodified"
            echo "::warning::Failed to edit existing PR #$existing_pr_number; keeping current PR body/title"
        fi
    else
        set +e
        create_output="$(gh pr create --base main --head "$branch" --title "chore(moltis): propose update to ${candidate_version}" --body-file "$body_file" 2>&1)"
        create_rc=$?
        set -e

        if [[ "$create_rc" -eq 0 ]]; then
            pr_url="$create_output"
            pr_mode="pr_created"
        elif grep -qi 'not permitted to create or approve pull requests' <<<"$create_output"; then
            pr_url="https://github.com/${GITHUB_REPOSITORY}/compare/main...${branch}?expand=1"
            pr_mode="manual_compare_url"
            echo "::notice::GitHub Actions token cannot create PR in this repository; using supported manual compare URL approval path"
        else
            echo "::error::Failed to create proposal PR: $create_output"
            exit "$create_rc"
        fi
    fi

    append_output "pr_url" "$pr_url"
    append_output "candidate_version" "$candidate_version"
    append_output "pr_mode" "$pr_mode"

    rm -f "$body_file"
}

main() {
    local command_name="${1:-}"
    if [[ -z "$command_name" ]]; then
        usage >&2
        exit 1
    fi
    shift || true

    case "$command_name" in
        prepare-branch)
            prepare_branch "$@"
            ;;
        sync-pr)
            sync_pr "$@"
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
