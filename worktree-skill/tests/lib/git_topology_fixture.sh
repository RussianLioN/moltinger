#!/usr/bin/env bash
set -euo pipefail

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
    printf '# fixture\n' > README.md
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
    printf '# fixture\n' > README.md
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

git_topology_fixture_add_worktree() {
  local repo_dir="$1"
  local worktree_path="$2"
  local branch_name="$3"

  (
    cd "${repo_dir}"
    git worktree add "${worktree_path}" "${branch_name}" >/dev/null
  )
}
