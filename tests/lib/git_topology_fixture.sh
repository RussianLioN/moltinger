#!/usr/bin/env bash
# Shared fixture helpers for git topology registry tests.

set -euo pipefail

git_topology_fixture_publish_branch_name() {
  printf '%s\n' "${GIT_TOPOLOGY_REGISTRY_PUBLISH_BRANCH:-chore/topology-registry-publish}"
}

git_topology_fixture_create_repo() {
  local fixture_root="$1"
  local repo_dir="${fixture_root}/repo"
  local origin_dir="${fixture_root}/origin.git"

  mkdir -p "${fixture_root}"
  git init --bare "${origin_dir}" >/dev/null
  git init "${repo_dir}" >/dev/null

  (
    cd "${repo_dir}"
    git config user.name "Topology Fixture"
    git config user.email "topology-fixture@example.test"
    git remote add origin "${origin_dir}"
    printf "# fixture\n" > README.md
    git add README.md
    git commit -m "fixture: initial commit" >/dev/null
    git branch -M main
    git push -u origin main >/dev/null
  )

  printf '%s\n' "${repo_dir}"
}

git_topology_fixture_create_named_repo() {
  local fixture_root="$1"
  local repo_name="$2"
  local repo_dir="${fixture_root}/${repo_name}"
  local origin_dir="${fixture_root}/${repo_name}.git"

  mkdir -p "${fixture_root}"
  git init --bare "${origin_dir}" >/dev/null
  git init "${repo_dir}" >/dev/null

  (
    cd "${repo_dir}"
    git config user.name "Topology Fixture"
    git config user.email "topology-fixture@example.test"
    git remote add origin "${origin_dir}"
    printf "# fixture\n" > README.md
    git add README.md
    git commit -m "fixture: initial commit" >/dev/null
    git branch -M main
    git push -u origin main >/dev/null
  )

  printf '%s\n' "${repo_dir}"
}

git_topology_fixture_add_branch() {
  local repo_dir="$1"
  local branch_name="$2"

  (
    cd "${repo_dir}"
    git switch -c "${branch_name}" >/dev/null
    printf '%s\n' "${branch_name}" > ".fixture-${branch_name}"
    git add ".fixture-${branch_name}"
    git commit -m "fixture: add ${branch_name}" >/dev/null
    git push -u origin "${branch_name}" >/dev/null
    git switch main >/dev/null
  )
}

git_topology_fixture_add_local_branch() {
  local repo_dir="$1"
  local branch_name="$2"
  local start_point="${3:-main}"

  (
    cd "${repo_dir}"
    git branch "${branch_name}" "${start_point}" >/dev/null
  )
}

git_topology_fixture_switch_branch() {
  local repo_dir="$1"
  local branch_name="$2"
  local start_point="${3:-}"

  (
    cd "${repo_dir}"
    if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
      git switch "${branch_name}" >/dev/null
    elif [[ -n "${start_point}" ]]; then
      git switch -c "${branch_name}" "${start_point}" >/dev/null
    else
      git switch -c "${branch_name}" >/dev/null
    fi
  )
}

git_topology_fixture_detach_head() {
  local repo_dir="$1"
  local target_ref="${2:-main}"

  (
    cd "${repo_dir}"
    git switch --detach "${target_ref}" >/dev/null
  )
}

git_topology_fixture_publish_worktree_path() {
  local repo_dir="$1"
  local publish_branch="$2"
  local repo_parent repo_name sanitized_branch

  repo_parent="$(cd "${repo_dir}/.." && pwd -P)"
  repo_name="$(basename "${repo_dir}")"
  sanitized_branch="$(printf '%s' "${publish_branch}" | tr '/:' '--' | tr -cd '[:alnum:]._-')"

  printf '%s/%s-%s\n' "${repo_parent}" "${repo_name}" "${sanitized_branch}"
}

git_topology_fixture_prepare_publish_worktree() {
  local repo_dir="$1"
  local publish_branch="$2"
  local start_point="${3:-}"
  local publish_path=""
  local effective_start_point=""
  local existing_worktree_path=""

  publish_path="$(git_topology_fixture_publish_worktree_path "${repo_dir}" "${publish_branch}")"

  existing_worktree_path="$(
    cd "${repo_dir}" &&
    git worktree list --porcelain |
      awk -v target_branch="refs/heads/${publish_branch}" '
        /^worktree / {
          if (current_branch == target_branch && current_path != "") {
            print current_path
            found = 1
            exit
          }
          current_path = substr($0, 10)
          current_branch = ""
          next
        }
        /^branch / {
          current_branch = $2
          next
        }
        END {
          if (!found && current_branch == target_branch && current_path != "") {
            print current_path
          }
        }
      '
  )"
  if [[ -n "${existing_worktree_path}" ]]; then
    printf '%s\n' "${existing_worktree_path}"
    return 0
  fi

  (
    cd "${repo_dir}"
    effective_start_point="${start_point}"
    if [[ -z "${effective_start_point}" ]]; then
      effective_start_point="$(git symbolic-ref --quiet --short HEAD || printf 'HEAD')"
    fi

    if [[ -e "${publish_path}" ]]; then
      :
    elif git show-ref --verify --quiet "refs/heads/${publish_branch}"; then
      git worktree add "${publish_path}" "${publish_branch}" >/dev/null
    else
      git worktree add -b "${publish_branch}" "${publish_path}" "${effective_start_point}" >/dev/null
    fi
  )

  printf '%s\n' "${publish_path}"
}

git_topology_fixture_copy_registry_assets_between_worktrees() {
  local asset_source_repo="$1"
  local metadata_source_repo="$2"
  local target_repo="$3"

  mkdir -p "${target_repo}/docs" "${target_repo}/scripts" "${target_repo}/.githooks"

  cp "${asset_source_repo}/scripts/git-topology-registry.sh" "${target_repo}/scripts/git-topology-registry.sh"
  cp "${asset_source_repo}/scripts/git-topology-registry-render.py" "${target_repo}/scripts/git-topology-registry-render.py"
  cp "${asset_source_repo}/.githooks/_repo-local-path.sh" "${target_repo}/.githooks/_repo-local-path.sh"
  cp "${asset_source_repo}/.githooks/pre-push" "${target_repo}/.githooks/pre-push"
  cp "${asset_source_repo}/.githooks/post-checkout" "${target_repo}/.githooks/post-checkout"
  cp "${asset_source_repo}/.githooks/post-merge" "${target_repo}/.githooks/post-merge"
  cp "${asset_source_repo}/.githooks/post-rewrite" "${target_repo}/.githooks/post-rewrite"

  if [[ -f "${metadata_source_repo}/docs/GIT-TOPOLOGY-INTENT.yaml" ]]; then
    cp "${metadata_source_repo}/docs/GIT-TOPOLOGY-INTENT.yaml" "${target_repo}/docs/GIT-TOPOLOGY-INTENT.yaml"
  fi

  if [[ -f "${metadata_source_repo}/docs/GIT-TOPOLOGY-REGISTRY.md" ]]; then
    cp "${metadata_source_repo}/docs/GIT-TOPOLOGY-REGISTRY.md" "${target_repo}/docs/GIT-TOPOLOGY-REGISTRY.md"
  fi

  chmod +x \
    "${target_repo}/scripts/git-topology-registry.sh" \
    "${target_repo}/scripts/git-topology-registry-render.py" \
    "${target_repo}/.githooks/_repo-local-path.sh" \
    "${target_repo}/.githooks/pre-push" \
    "${target_repo}/.githooks/post-checkout" \
    "${target_repo}/.githooks/post-merge" \
    "${target_repo}/.githooks/post-rewrite"
}

git_topology_fixture_add_worktree() {
  local repo_dir="$1"
  local worktree_path="$2"
  local branch_name="$3"

  (
    cd "${repo_dir}"
    git worktree add "${worktree_path}" "${branch_name}" >/dev/null
  )
}

git_topology_fixture_add_worktree_branch_from() {
  local repo_dir="$1"
  local worktree_path="$2"
  local new_branch="$3"
  local start_point="$4"

  (
    cd "${repo_dir}"
    git worktree add -b "${new_branch}" "${worktree_path}" "${start_point}" >/dev/null
  )
}

git_topology_fixture_refresh_registry_from_publish_branch() {
  local repo_dir="$1"
  local registry_script="${2:-}"
  local publish_branch="${3:-$(git_topology_fixture_publish_branch_name)}"
  local start_point="${4:-}"
  local asset_source_repo=""
  local publish_path=""

  publish_path="$(git_topology_fixture_prepare_publish_worktree "${repo_dir}" "${publish_branch}" "${start_point}")"
  asset_source_repo="${repo_dir}"
  if [[ ! -f "${asset_source_repo}/scripts/git-topology-registry.sh" && -n "${registry_script}" ]]; then
    asset_source_repo="$(cd "$(dirname "${registry_script}")/.." && pwd -P)"
  fi
  git_topology_fixture_copy_registry_assets_between_worktrees "${asset_source_repo}" "${repo_dir}" "${publish_path}"

  (
    cd "${publish_path}"
    ./scripts/git-topology-registry.sh refresh --write-doc >/dev/null
  )

  mkdir -p "${repo_dir}/docs"
  cp "${publish_path}/docs/GIT-TOPOLOGY-REGISTRY.md" "${repo_dir}/docs/GIT-TOPOLOGY-REGISTRY.md"
}

git_topology_fixture_doctor_write_doc_from_publish_branch() {
  local repo_dir="$1"
  local registry_script="${2:-}"
  local publish_branch="${3:-$(git_topology_fixture_publish_branch_name)}"
  local start_point="${4:-}"
  local asset_source_repo=""
  local publish_path=""

  publish_path="$(git_topology_fixture_prepare_publish_worktree "${repo_dir}" "${publish_branch}" "${start_point}")"
  asset_source_repo="${repo_dir}"
  if [[ ! -f "${asset_source_repo}/scripts/git-topology-registry.sh" && -n "${registry_script}" ]]; then
    asset_source_repo="$(cd "$(dirname "${registry_script}")/.." && pwd -P)"
  fi
  git_topology_fixture_copy_registry_assets_between_worktrees "${asset_source_repo}" "${repo_dir}" "${publish_path}"

  (
    cd "${publish_path}"
    ./scripts/git-topology-registry.sh doctor --prune --write-doc >/dev/null
  )

  mkdir -p "${repo_dir}/docs"
  cp "${publish_path}/docs/GIT-TOPOLOGY-REGISTRY.md" "${repo_dir}/docs/GIT-TOPOLOGY-REGISTRY.md"
}

git_topology_fixture_seed_registry_assets() {
  local repo_dir="$1"
  local project_root="$2"

  mkdir -p "${repo_dir}/docs" "${repo_dir}/scripts" "${repo_dir}/.githooks"

  cp "${project_root}/scripts/git-topology-registry.sh" "${repo_dir}/scripts/git-topology-registry.sh"
  cp "${project_root}/scripts/git-topology-registry-render.py" "${repo_dir}/scripts/git-topology-registry-render.py"
  cp "${project_root}/.githooks/_repo-local-path.sh" "${repo_dir}/.githooks/_repo-local-path.sh"
  cp "${project_root}/.githooks/pre-push" "${repo_dir}/.githooks/pre-push"
  cp "${project_root}/.githooks/post-checkout" "${repo_dir}/.githooks/post-checkout"
  cp "${project_root}/.githooks/post-merge" "${repo_dir}/.githooks/post-merge"
  cp "${project_root}/.githooks/post-rewrite" "${repo_dir}/.githooks/post-rewrite"

  chmod +x \
    "${repo_dir}/.githooks/_repo-local-path.sh" \
    "${repo_dir}/scripts/git-topology-registry.sh" \
    "${repo_dir}/scripts/git-topology-registry-render.py" \
    "${repo_dir}/.githooks/pre-push" \
    "${repo_dir}/.githooks/post-checkout" \
    "${repo_dir}/.githooks/post-merge" \
    "${repo_dir}/.githooks/post-rewrite"
}

git_topology_fixture_remove_worktree() {
  local repo_dir="$1"
  local worktree_path="$2"

  (
    cd "${repo_dir}"
    git worktree remove "${worktree_path}" --force >/dev/null
  )
}

git_topology_fixture_delete_branch() {
  local repo_dir="$1"
  local branch_name="$2"

  (
    cd "${repo_dir}"
    git branch -D "${branch_name}" >/dev/null
    git push origin --delete "${branch_name}" >/dev/null 2>&1 || true
  )
}
