# Moltis Official Skill Runtime Contract

**Date**: 2026-03-27  
**Purpose**: зафиксировать официальный runtime-контракт Moltis для skills и убрать проектную путаницу между repo source path и live discovery path.

## Executive Summary

- Официальная документация Moltis для self-extension говорит, что personal skills создаются в `<data_dir>/skills/<name>/`.
- Официальный upstream-код discovery сейчас сканирует два runtime-default пути: `<data_dir>/skills/` и `<data_dir>/.moltis/skills/`.
- В production Moltinger repo `skills/` не должен считаться live path сам по себе.
- Для GitOps-managed skills репозиторий остаётся source of truth, а deploy обязан материализовать repo skill в официальный runtime-discovered каталог и после этого доказать discovery через live runtime.

## Official Sources

### 1. Official docs

- `https://docs.moltis.org/skill-tools.html`
  - `create_skill` пишет новый `SKILL.md` в `<data_dir>/skills/<name>/`.
  - `update_skill`, `patch_skill` и `delete_skill` работают с тем же personal skill path.
  - `write_skill_files` доступен при включённом `enable_agent_sidecar_files`.

- `https://docs.moltis.org/configuration.html`
  - документирует `[skills] enabled`, `auto_load` и `enable_agent_sidecar_files`;
  - не даёт production-proof, что одного `search_paths` достаточно для всех runtime surfaces.

### 2. Official upstream code

Snapshot checked on `2026-03-27`: `moltis-org/moltis`.

- `crates/skills/src/discover.rs`
  - `FsSkillDiscoverer::default_paths()` возвращает:
    - `<data_dir>/.moltis/skills` as `Project`
    - `<data_dir>/skills` as `Personal`
    - installed registry/plugin paths

- `crates/chat/src/lib.rs`
  - prompt injection uses `FsSkillDiscoverer::default_paths()`

- `crates/gateway/src/server.rs`
  - skill watcher is built from `default_paths()`
  - built-in `template-skill` и `tmux` seed-ятся через `seed_skill_if_missing()` в `<data_dir>/skills/<name>/`

- `crates/web/src/api.rs`
  - `/api/skills` lists discovered skills from runtime-default paths; in production this remains valid live proof only after authenticating through the official auth flow.

## What This Means For Moltinger

### Repo path vs live path

- `skills/` в репозитории: Git source of truth
- `/server/skills` в контейнере: container-visible repo source, но не authoritative discovery proof
- runtime-discovered skill path in our deployment: `/home/moltis/.moltis/skills`

Почему именно так в production:

- live Moltis logs already show the watcher on `/home/moltis/.moltis/skills`;
- this path persists inside the mounted Moltis data volume;
- it avoids claiming that `search_paths=/server/skills` alone is sufficient when official runtime evidence does not prove that.

## Production Contract

For GitOps-managed skills in Moltinger:

1. edit the skill under repo `skills/<name>/`
2. deploy the tracked repo through GitOps
3. during deploy, sync repo-managed skills into `/home/moltis/.moltis/skills`
4. verify discovery through an authenticated live `/api/skills` request
5. keep `auto_load` only as an activation hint after discovery, not as an import mechanism

## Verification Contract

The minimum acceptable proof is runtime-first:

1. synced file exists in `/home/moltis/.moltis/skills/<name>/SKILL.md`
2. authenticated `GET /api/skills` exposes the skill name
3. one technical canary request can use the skill without falling back to generic reasoning

Not sufficient on its own:

- repo file exists under `skills/`
- `/server/skills` exists in the container
- `search_paths` mentions `/server/skills`

## Decision

For this repository, the canonical rule is:

- do not treat `/server/skills` as live discovery contract;
- do treat repo `skills/` as Git-managed source content;
- do treat `/home/moltis/.moltis/skills` plus authenticated live `/api/skills` as the production discovery proof.
