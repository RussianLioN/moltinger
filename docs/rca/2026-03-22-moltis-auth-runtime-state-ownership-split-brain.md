---
title: "Moltis auth and durable runtime state drifted because ownership was split across tracked config, rendered env, and backup inventory"
date: 2026-03-22
severity: P2
category: configuration
tags: [moltis, auth, telegram, backup, runtime-state, gitops, rca]
root_cause: "The repository treated auth, allowlist, and runtime-state durability as related concerns but did not enforce one canonical ownership contract across config, CI env rendering, preflight, compose, and backup readiness."
---

# RCA: Moltis auth and durable runtime state drifted because ownership was split across tracked config, rendered env, and backup inventory

## Summary

While closing the durability backlog, two related gaps surfaced:

1. `MOLTINGER_SERVICE_TOKEN` was declared as the fleet auth contract in `config/moltis.toml` and policy metadata, but CI did not render it into `/opt/moltinger/.env`, and the Moltis container did not receive it explicitly.
2. Telegram allowlist ownership was ambiguous: real Moltis ingress was tracked in `config/moltis.toml`, while auxiliary tooling still looked at `TELEGRAM_ALLOWED_USERS` as if it were an independent source of truth.
3. Backup restore-readiness covered tracked config and data, but not the full Moltis runtime state split across `${MOLTIS_RUNTIME_CONFIG_DIR}` and `~/.moltis`.

None of these gaps had to be live incidents every time, but together they made the deployment fragile and easy to misdiagnose.

## Error

The repository had a split-brain contract for Moltis runtime durability:

- one source defined auth intent
- another source rendered runtime env
- a third source carried Telegram allowlist assumptions
- backup inventory omitted part of the actual runtime state

This created a high chance of silent drift, confusing troubleshooting, and incomplete recovery.

## 5 Whys

1. Why could Moltis auth/runtime drift silently?
   Because required runtime auth/state lived across tracked config, CI-rendered `.env`, writable runtime config, and `~/.moltis`, but not all layers were validated together.
2. Why were those layers not validated together?
   Because hardening landed incrementally around specific incidents such as OAuth/runtime mount drift, not as one explicit ownership contract.
3. Why did `MOLTINGER_SERVICE_TOKEN` specifically fall through?
   Because it was modeled in tracked config and fleet policy, but the shared Moltis env renderer and deploy workflows never rendered it into the server `.env`.
4. Why was Telegram allowlist still confusing?
   Because runtime ingress auth had already moved to tracked `config/moltis.toml`, but docs and auxiliary tooling still treated `TELEGRAM_ALLOWED_USERS` like a primary auth source.
5. Why did backup/restore remain incomplete?
   Because restore-readiness originally focused on git-synced config plus `data/`, while Moltis durable runtime state also lives in `${MOLTIS_RUNTIME_CONFIG_DIR}` and `~/.moltis`.

## Root Cause

The repository lacked a single enforced ownership model for Moltis auth and durable runtime state. The intent existed, but the enforcement boundary between tracked config, rendered env, runtime mounts, and recovery artifacts was incomplete.

## Evidence

- `config/moltis.toml` bound fleet service auth to `MOLTINGER_SERVICE_TOKEN`.
- `config/moltis.toml` already used tracked Telegram `dm_policy = "allowlist"` with explicit `allowlist = [...]`.
- `.github/workflows/deploy.yml` and `.github/workflows/uat-gate.yml` rendered Moltis `.env` without `MOLTINGER_SERVICE_TOKEN`.
- `scripts/render-moltis-env.sh` previously accepted `TELEGRAM_ALLOWED_USERS` as free input instead of deriving or validating it against tracked config.
- `scripts/backup-moltis-enhanced.sh` previously marked restore readiness without archiving `${MOLTIS_RUNTIME_CONFIG_DIR}` and the Moltis runtime home.

## Fix

1. Added fail-closed rendering of `MOLTINGER_SERVICE_TOKEN` into the shared Moltis `.env` renderer.
2. Made `TELEGRAM_ALLOWED_USERS` in the rendered `.env` derive from tracked `config/moltis.toml`, and fail if an override diverges from tracked allowlist intent.
3. Updated deploy/UAT workflows to pass `MOLTINGER_SERVICE_TOKEN` and stop treating `TELEGRAM_ALLOWED_USERS` GitHub Secret input as the deploy-time source of truth.
4. Added preflight validation that Moltis keeps:
   - `MOLTIS_FLEET_SERVICE_TOKEN_ENV = "MOLTINGER_SERVICE_TOKEN"`
   - Telegram `dm_policy = "allowlist"`
   - non-empty tracked Telegram allowlist
5. Extended backup restore-readiness to archive and verify:
   - `${MOLTIS_RUNTIME_CONFIG_DIR}`
   - Moltis runtime home (`~/.moltis` / `moltis-data`)
   - runtime evidence manifest

## Verification

- `bash tests/component/test_backup_restore_readiness.sh` -> `1/1 PASS`
- `bash tests/unit/test_deploy_workflow_guards.sh` -> `30/30 PASS`
- `bash tests/static/test_config_validation.sh` -> `104/104 PASS`
- `bash tests/component/test_moltis_session_reconcile.sh` -> `2/2 PASS`

## Preventive Actions

1. Keep tracked config as the authoritative Moltis Telegram ingress allowlist.
2. Treat `/opt/moltinger/.env` as a rendered runtime mirror, not as an independent configuration source.
3. Keep `MOLTINGER_SERVICE_TOKEN` in the shared env renderer, workflows, and compose contract together.
4. Keep restore-readiness fail-closed unless runtime config and runtime home archives are both present.
5. Update operator docs and self-learning docs when auth ownership rules change, so future sessions do not revive retired assumptions.

## Lessons

1. “Secret exists somewhere” is not enough; the repository must prove it reaches the exact runtime surface that consumes it.
2. If a config value is authoritative in git, any `.env` mirror must be derived or validated against that tracked value rather than maintained manually.
3. Backup contracts for agent runtimes must include writable runtime config and runtime home, not just tracked config plus one generic data directory.
