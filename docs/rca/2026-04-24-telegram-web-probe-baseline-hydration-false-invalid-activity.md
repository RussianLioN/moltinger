---
title: "Telegram Web probe treated hydrated historical chat bubbles as fresh pre-send invalid activity"
date: 2026-04-24
status: resolved
severity: medium
category: telegram
tags: [telegram, uat, playwright, probe, false-negative, hydration]
root_cause: "The authoritative Telegram Web probe established its pre-send baseline before the visible chat DOM had finished hydrating, so an old leaked assistant bubble appeared after baseline capture and was misclassified as fresh invalid incoming activity."
---

# RCA: Telegram Web probe treated hydrated historical chat bubbles as fresh pre-send invalid activity

## Summary

Authoritative Telegram Web UAT for skill-creation turns failed with `pre_send_invalid_activity` even after the production runtime fix had already been deployed. The probe kept reporting the same historical leaked message:

`Не могу создать в этой сессии: create_skill сломан и возвращает missing 'name' даже при корректном вызове.`

The underlying runtime was no longer proven broken by that point. The failing boundary was the repo-owned authoritative probe itself: it captured a pre-send baseline too early, before Telegram Web had finished hydrating the visible chat snapshot after opening the dialog.

## Impact

- Post-deploy authoritative UAT produced a false negative and blocked further user-imitation testing.
- Operators were pushed toward `clear or reconcile the chat/session noise` even though the same stale bubble was being rediscovered from already-existing history.
- The repair lane for Telegram skill creation could not be cleanly verified end-to-end until the probe contract was corrected.

## Evidence

- Authoritative runs `24872927003`, `24873093295`, and `24873203337` all failed with `pre_send_invalid_activity`.
- The offending bubble kept the same `mid=221721` across reruns, which is inconsistent with a newly generated live reply and consistent with historical message hydration.
- Review-safe and restricted-debug artifacts both showed:
  - `failure.code = pre_send_invalid_activity`
  - `baseline_max_message_id = 221721`
  - `last_pre_send_activity.messages[0].mid = 221721`
- `scripts/telegram-web-user-probe.mjs` previously did:
  1. `openTargetChat(...)`
  2. immediate `collectMessages(...)`
  3. use that first snapshot as `baselineMaxMid`
  4. enter `waitForQuietWindow(...)`
  5. fail on any invalid incoming seen after that baseline

## Why It Happened

| Why | Answer | Evidence |
| --- | --- | --- |
| 1 | Why did authoritative UAT fail before sending the new probe message? | Because `pre_send_invalid_activity` fired during quiet-window evaluation. | `scripts/telegram-web-user-probe.mjs` |
| 2 | Why did quiet-window evaluation think there was fresh invalid incoming activity? | Because a leaked assistant bubble appeared after the initial baseline snapshot and was therefore treated as `newMessages`. | `waitForQuietWindowWithCollector(...)` in `scripts/telegram-web-user-probe.mjs` |
| 3 | Why could an old bubble appear after baseline capture? | Telegram Web had not finished hydrating the visible chat DOM immediately after `openTargetChat(...)`. | repeated runs with the exact same `mid=221721` |
| 4 | Why did the probe not absorb that hydration before starting the quiet-window guard? | There was no dedicated visible-baseline stabilization step between `openTargetChat(...)` and `waitForQuietWindow(...)`. | `scripts/telegram-web-user-probe.mjs` before fix |
| 5 | Why is this a source-contract defect rather than operator noise? | Because the authoritative repo-owned probe defined the decision boundary and misclassified already-existing history as fresh recent invalid activity. | repeated authoritative failures after runtime fix deploy |

## Root Cause

The repo-owned authoritative Telegram Web probe captured its pre-send baseline before the visible chat snapshot had stabilized. Historical bubbles that were merely hydrated into the DOM after chat-open were then reclassified as fresh `newMessages`, and invalid ones triggered `pre_send_invalid_activity` before the probe could send the new operator message.

## Fix

1. Added a visible-baseline stabilization phase in `scripts/telegram-web-user-probe.mjs` before quiet-window guarding:
   - `stabilizeVisibleBaselineWithCollector(...)`
   - new defaults:
     - `TELEGRAM_WEB_BASELINE_STABILIZE_MS=1200`
     - `TELEGRAM_WEB_BASELINE_STABILIZE_MAX_WAIT_MS=4000`
2. The authoritative flow now:
   - opens the target chat
   - waits for the visible bubble snapshot to stop changing
   - uses that stabilized max `mid` as the real pre-send baseline
   - only then runs `waitForQuietWindow(...)`
3. Added regression coverage in `tests/component/test_telegram_web_probe_correlation.sh` for the exact historical hydration pattern:
   - stale invalid bubble appears only after initial empty snapshot
   - stabilized baseline absorbs it
   - quiet-window no longer treats it as fresh pre-send invalid activity

## Validation

- `node --check scripts/telegram-web-user-probe.mjs`
- `bash tests/component/test_telegram_web_probe_correlation.sh`

## Уроки

1. В authoritative browser-based UAT нельзя считать первый видимый chat snapshot истинным baseline сразу после открытия чата; сначала нужен явный stabilization step для DOM hydration.
2. Если один и тот же `mid` воспроизводится в `pre_send_invalid_activity` на нескольких прогонах, это сильный сигнал ложного probe-boundary fail, а не обязательного live runtime regression.
3. Repo-owned UAT boundary должен различать active incoming noise и historical chat hydration, иначе post-deploy verification превращается в ложный блокер.

## Follow-ups

1. Re-run authoritative Telegram Web UAT after deploy on the same skill-creation prompt to verify that the false `pre_send_invalid_activity` is gone.
2. Continue the planned user-imitation dialog sequence for:
   - `codex-update`
   - duplicate-notification explanation
   - create/update/delete of a new Moltis version-watch skill
