# Implementation Plan: Full Moltis-Native Codex Update Skill

**Branch**: `023-full-moltis-codex-update-skill` | **Date**: 2026-03-14 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/023-full-moltis-codex-update-skill/spec.md`

## Summary

Replace the current hybrid `repo-side watcher + Moltis UX` model with a fully Moltis-native Codex update capability. The canonical runtime will move into Moltis skill/agent surfaces for on-demand checks, scheduled polling, state/fingerprint storage, Telegram delivery, and optional project-profile-based recommendations.

## Technical Context

**Language/Version**: Bash + Moltis skill/runtime configuration in the current repo  
**Primary Dependencies**: `config/moltis.toml`, `skills/`, `scripts/telegram-bot-send.sh`, Moltis hook/runtime surfaces, current Codex changelog parser logic, `jq`, `python3`  
**Storage**: Moltis-owned local state under `.tmp/current/` and `/opt/moltinger/.tmp/current/` until a more native Moltis persistence surface is chosen  
**Testing**: shell component tests, hermetic E2E helpers, targeted live UAT after rollout  
**Target Platform**: Moltis on `ainetic.tech` plus local hermetic test environment  
**Project Type**: single deployable Moltis repo with scripts, config, skills, docs, tests  
**Performance Goals**: one upstream polling cycle within existing cron/SLA expectations; duplicate suppression deterministic; on-demand answer within interactive chat expectations  
**Constraints**: GitOps-managed runtime, Russian human-facing UX, safe degraded mode, no revival of repo-side `/codex_*` UX  
**Scale/Scope**: one canonical Codex update skill supporting both scheduled and on-demand execution, plus optional multi-project profile inputs later

## Constitution Check

- **GitOps discipline**: PASS. New capability must be configured and deployed through repo-managed skills/config/scripts only.
- **Single owner of Telegram UX**: PASS. Moltis remains the only live owner of Telegram ingress and dialogue.
- **No hidden runtime split**: PASS if repo-side watcher is demoted from canonical runtime to migration-only material.
- **Safe degraded mode**: PASS. One-way alert and manual on-demand check remain valid fallback paths.

## Project Structure

### Documentation (this feature)

```text
specs/023-full-moltis-codex-update-skill/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- tasks.md
|-- checklists/
|   `-- requirements.md
`-- contracts/
    `-- project-profile.schema.json
```

### Planned Runtime Surface

```text
skills/
`-- codex-update/
    `-- SKILL.md                    # Moltis-native user-facing skill

scripts/
|-- moltis-codex-update-run.sh     # canonical runtime entrypoint (manual + scheduler)
|-- moltis-codex-update-state.sh   # fingerprint/state helper
|-- moltis-codex-update-profile.sh # optional project profile validation/loading
`-- telegram-bot-send.sh           # reused sender

config/
`-- moltis.toml                    # skills auto-load, scheduler/config wiring

docs/
`-- moltis-codex-update-skill.md   # operator and product runbook

tests/
`-- component/
    |-- test_moltis_codex_update_run.sh
    |-- test_moltis_codex_update_state.sh
    `-- test_moltis_codex_update_profile.sh
```

## Phase Plan

### Phase 0 - Re-baseline and Migration Boundary

- Freeze current hybrid `012/021/ewde` path as migration-only context.
- Document that canonical ownership is moving into a Moltis-native skill.
- Define which existing parser/report pieces are temporarily reused and which are retired.

### Phase 1 - Moltis Skill Core

- Create Moltis-native `codex-update` skill entrypoint under `skills/`.
- Implement canonical run helper for on-demand checks.
- Add Moltis-owned state/fingerprint helper.

### Phase 2 - Scheduler and Delivery

- Move scheduled polling and duplicate suppression into Moltis-native runtime wiring.
- Reuse Telegram sender through Moltis-owned runtime.
- Keep safe one-way fallback available.

### Phase 3 - Optional Project Profiles

- Define stable project profile contract.
- Allow generic advisory without any profile.
- Add project-specific recommendation rendering when profile exists.

### Phase 4 - Observability and Rollout

- Add machine-readable audit/state records.
- Document operator flow and rollback.
- Perform live rollout after hermetic proof.

## Risk Register

1. **Migration confusion**
   - Risk: old repo-side watcher remains treated as canonical by docs or ops.
   - Mitigation: explicit deprecation notes and new skill-first docs.
2. **Duplicate logic during transition**
   - Risk: same polling or advisory logic exists in both places temporarily.
   - Mitigation: one migration map in docs/research and explicit removal tasks.
3. **Profile overreach**
   - Risk: project-specific logic makes Moltis depend on repo internals.
   - Mitigation: keep profile contract static and optional.
4. **Production rollout drift**
   - Risk: server/runtime not on the expected revision during enablement.
   - Mitigation: separate rollout phase and explicit UAT issue.
