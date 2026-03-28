---
title: "Moltis stale browser session cache and Telegram logbook leakage remained after repo-side browser hardening"
date: 2026-03-28
severity: P1
category: reliability
tags: [moltis, browser, telegram, activity-log, upstream, sandbox, openclaw]
root_cause: "The remaining live failure moved past repo-owned Docker/profile fixes into upstream runtime behavior: stale browser session reuse after browser death plus Telegram delivery of channel activity/status logbook."
---

# RCA: Moltis stale browser session cache and Telegram logbook leakage remained after repo-side browser hardening

## Summary

После того как в `main` уже были закрыты repo-owned browser issues
(`docker.sock`, sibling-container routing, tracked browser image, writable profile dir,
single-instance ephemeral profile),
пользовательский Telegram path всё ещё давал:

- `⚠️ Timed out: Agent run timed out after 30s`
- `📋 Activity log`
- browser failures вида:
  - `browser connection dead, closing session and retrying`
  - `pool exhausted: no browser instances available`

Новая decisive evidence показала, что remaining defect уже не сводится к tracked repo config.

## Evidence

### 1. Live RPC / logs

- В отдельной operator browser canary session первый browser tool call начинался с raw
  `session_id: null`.
- В тот же run live manager log уже показывал browser request с
  `session_id="browser-027f2350dc1ebb16"`.
- После browser death live logs показывали:
  - `browser connection dead, closing session and retrying`
  - `pool exhausted: no browser instances available`
- Telegram user-facing reply содержал internal suffix/logbook:
  - `📋 Activity log`
  - tool names
  - `Navigating to t.me/tsingular`

### 2. Upstream code path

По upstream code inspection:

- browser tool reuse привязан к session-scoped cache;
- cache cleanup привязан к explicit `close`, а не доказанно к browser-death path;
- Telegram outbound path может дописывать internal channel status log/suffix к обычной
  доставке пользователю.

### 3. Official-first baseline

Official docs говорят следующее:

- browser sandbox mode автоматически следует session sandbox mode, а не отдельному pairing
  state:
  - https://docs.moltis.org/browser-automation.html
- для Docker-in-Docker требуется sibling-container contract и host-visible path:
  - https://docs.moltis.org/browser-automation.html
  - https://docs.moltis.org/sandbox.html
- OpenClaw `Pairing` относится к owner approval / DM pairing / node pairing, а не к browser
  session cleanup:
  - https://docs.openclaw.ai/channels/pairing
- OpenClaw sandbox docs operationally ведут к sandbox recreate/reset после config/runtime
  drift, а не к UI pair-click как default browser fix:
  - https://docs.openclaw.ai/gateway/sandboxing

## 5 Whys

### 1. Почему Telegram user path всё ещё уходил в timeout и `Activity log`?

Потому что browser run сначала умирал на browser/session lifecycle failure, а затем
Telegram delivery path публиковал internal activity/status trace как обычное сообщение.

### 2. Почему browser run умирал уже после предыдущих browser fixes?

Потому что remaining failure moved deeper:
repo-fixed launch/storage/connectivity contract уже был зелёным,
но stale browser session/cache invalidation после `connection dead` оставалась broken.

### 3. Почему мы не можем честно закрыть это только prompt/config-правкой?

Потому что prompt guardrail может снизить вероятность browser-heavy path, но не управляет
upstream cache invalidation и Telegram outbound suffix behavior.

### 4. Почему гипотеза “надо заново Pair” не доказана?

Потому что official Pair docs относятся к DM/node approval,
а текущая evidence показывает active send/reply path и browser/session failure shape, а не
missing authorization or missing paired state.

### 5. Почему это всё равно требует repo-side действий?

Потому что репозиторий владеет:

- operator diagnostics;
- fail-closed UAT/smoke classification;
- temporary containment on Telegram user path;
- official-first runbook/rule/lessons;
- качественным upstream handoff вместо гадания.

## Root Cause

### Primary root cause

Remaining live defect находится в upstream/runtime boundary:

- stale browser session/cache survives browser-death path;
- Telegram outbound/status-logbook path leaks internal activity into user-facing chat.

### Contributing root cause

Repo до этого момента ещё не имел:

- явного degraded-mode для Telegram browser/search/memory-heavy flows;
- targeted failure taxonomy for stale browser session contamination;
- explicit official-first runbook statement, что Pair не является default fix для такого
  incident.

## Repo-Owned Fix

1. Добавить temporary degraded-mode в `config/moltis.toml` для user-facing Telegram/DM path.
2. Научить `scripts/test-moltis-api.sh` отдельно классифицировать:
   - `browser_session_contamination`
   - `browser_pool_exhausted`
   - `browser_navigation_timeout`
3. Расширить browser canary reject signatures на:
   - `browser connection dead`
   - `pool exhausted: no browser instances available`
4. Зафиксировать official-first runbook/rule/consilium/upstream issue artifact.

## Upstream-Owned Fix

Closure по инциденту требует upstream/runtime repair:

1. browser session/cache must be invalidated after `connection dead` and timeout paths;
2. Telegram outbound path must not leak `channel_status_log` / `Activity log` into
   user-facing chat by default;
3. browser failure recovery must not collapse into `PoolExhausted` on subsequent runs.

## Verification

- `bash -n scripts/test-moltis-api.sh`
- `bash -n scripts/moltis-browser-canary.sh`
- `bash tests/component/test_moltis_api_smoke.sh`
- `bash tests/component/test_moltis_browser_canary.sh`
- `bash tests/static/test_config_validation.sh`

## Prevention

- Не считать repo-side browser repair завершённой, пока не доказаны:
  - clean `t.me/...` browser canary;
  - no stale browser session reuse after browser death;
  - no Telegram `Activity log` leak.
- Не использовать `Pair` как default action при browser/session incident без
  доказанного pairing/auth drift.
- Любой post-fix live symptom, который меняет shape от предыдущего RCA, оформлять как новую
  корневую причину, а не продолжать “долечивать” старый симптом.
