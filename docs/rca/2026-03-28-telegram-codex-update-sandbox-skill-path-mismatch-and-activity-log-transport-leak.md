---
title: "Telegram codex-update false negative came from sandbox skill-path mismatch while Activity log leakage survived transport-level filtering"
date: 2026-03-28
severity: P1
category: reliability
tags: [moltis, telegram, codex-update, skills, sandbox, activity-log, upstream, openclaw]
root_cause: "The live runtime advertised codex-update as an available skill, but Telegram sandboxed exec could not see the advertised host paths, so the model used false filesystem probes. Separately, Telegram still surfaced internal activity outside the clean final assistant reply."
---

# RCA: Telegram codex-update sandbox mismatch and Activity log transport leakage

## Summary

Пользователь получил сразу две связанные проблемы в live Telegram path:

1. Moltis перечислил `codex-update` среди доступных навыков, а затем ответил так, будто skill path не существует.
2. В тот же пользовательский чат снова попал `📋 Activity log`.

Ключевой факт: это не один и тот же дефект.

- `codex-update` false negative возник из-за несоответствия между advertised skill contract в raw prompt и реальной видимостью файлов внутри sandboxed `exec`.
- `Activity log` leakage произошёл на channel delivery/transport boundary, потому что финальный assistant reply в истории был чистым, а служебный лог пользователю всё равно показался отдельным artifact.

## Evidence

### 1. Live skill truth

Authoritative runtime evidence showed:

- authenticated `/api/skills` returned `codex-update` as enabled;
- live runtime skills dir on the host/container included `codex-update`;
- tracked config already had:
  - `[skills] enabled = true`
  - `auto_load = ["telegram-learner", "codex-update"]`

This proves the skill was not simply “missing from deployment”.

### 2. Live Telegram session evidence

Authoritative `chat.history` for the active Telegram session showed:

- user asked `Что с новыми версиями codex?`
- tool path tried `cat /home/moltis/.moltis/skills/codex-update/SKILL.md`
- tool path tried `find /home/moltis/.moltis/skills ...`
- both probes failed
- assistant then replied that the skill path and skills directory did not exist

### 3. Raw prompt vs sandbox filesystem mismatch

Authoritative `chat.raw_prompt` for the same live session showed:

- workspace path advertised as `/home/moltis/.moltis`
- available skills listed with paths under `/home/moltis/.moltis/skills/...`
- instruction to activate a skill by reading its `SKILL.md`

But inside the actual session sandbox container:

- `/home/moltis/.moltis/skills` did not exist
- `/server` did not exist
- only a limited subset such as browser/sandbox state was visible

So the model was instructed to activate a skill through paths that the sandboxed `exec`
surface could not actually read.

### 4. Activity log leakage was not the same as final answer text

Authoritative `chat.history` showed a clean final assistant reply, not an `Activity log`
message as the final assistant turn.

At the same time, the user still saw `📋 Activity log` in Telegram.

This means:

- the leak did not come only from the final assistant reply content;
- it survived somewhere in channel delivery / transport / status rendering.

### 5. Official-first baseline

Official docs and official issue surface supported the split diagnosis:

- Moltis skill/channel docs define runtime skills and channel behavior as live runtime contracts, not as ad hoc filesystem guesses.
- OpenClaw sandbox docs describe Docker sandbox behavior and container constraints, including default Docker network and write restrictions.
- OpenClaw pairing docs describe pairing/approval semantics, not skill-path visibility or browser/session cleanup.
- Official OpenClaw issues already show active Telegram/runtime instability signals such as:
  - `Telegram: multi-minute silence during tool-heavy turns and compaction — operator has no visibility`
  - `Voice-call plugin ignores agents.defaults.sandbox.mode: "off" - forces Docker sandbox for voice lane responses`

## 5 Whys

### 1. Почему bot соврал, что `codex-update` не существует?

Потому что он опирался на sandboxed filesystem probes по путям, которые live runtime рекламировал,
но конкретная Telegram `exec` surface не видела.

### 2. Почему модель вообще пошла в filesystem probes?

Потому что raw prompt поощрял activation contract через reading `SKILL.md` at host-style paths,
а user-facing prompt contract недостаточно явно запрещал использовать такие probes как truth.

### 3. Почему это не просто “skill forgot to sync”?

Потому что `/api/skills` и live runtime discovery уже подтвердили наличие `codex-update`.

### 4. Почему `Activity log` leak не объясняется просто `stream_mode = "on"`?

Потому что authoritative `channels.list` уже показывал `stream_mode = "off"`,
а final assistant reply в history был чистым.

### 5. Почему всё же нужны repo-side fixes?

Потому что репозиторий владеет:

- identity/prompt guardrails;
- authoritative Telegram UAT contracts;
- documentation, rules, runbook and lessons;
- upstream issue handoff quality.

## Root Cause

### Primary root cause

Prompt/runtime/sandbox contract mismatch:

- runtime advertised `codex-update` as available;
- raw prompt told the model to activate the skill by reading host-style paths;
- sandboxed Telegram `exec` could not actually read those paths;
- model converted “path not visible in sandbox” into the false statement “skill does not exist”.

### Secondary root cause

Transport-level Telegram leakage:

- internal activity/status content still escaped into the user-facing chat path outside the clean final assistant turn.

## Repo-Owned Fix

1. Strengthen `identity.soul` so Telegram/sandboxed sessions:
   - do not use `/home/moltis/.moltis/skills` or `/server` file probes as skill truth;
   - treat `codex-update` as advisory-only on remote user-facing surfaces;
   - do not promise remote execution of local Codex update actions.
2. Extend authoritative Telegram UAT to fail on:
   - host path leakage;
   - `codex-update` false-negative replies;
   - `Activity log` leakage.
3. Record the remote-safe `codex-update` redesign as explicit backlog.

## Upstream-Owned Fix

Closure requires upstream/runtime correction:

1. skill activation contract should not advertise host paths that sandboxed `exec` cannot read;
2. or the sandbox should expose the required skill/runtime surface consistently;
3. Telegram delivery path should not emit `Activity log` to the end user when the final assistant message is already clean.

## Verification

- `bash -n scripts/telegram-e2e-on-demand.sh`
- `bash tests/component/test_telegram_remote_uat_contract.sh`
- `bash tests/static/test_config_validation.sh`

## Prevention

- Do not use sandbox file visibility as proof that a live-discovered skill is missing.
- For remote Moltis surfaces, treat `codex-update` as advisory/notification capability until its full redesign lands.
- If Telegram user sees `Activity log` but `chat.history` final reply is clean, classify it as transport/delivery leakage and escalate accordingly.

