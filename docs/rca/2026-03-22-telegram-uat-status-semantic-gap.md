---
title: "Authoritative Telegram UAT still had semantic false-green gaps for /status and exercised surfaces"
date: 2026-03-22
severity: P2
category: qa
tags: [telegram, uat, semantic-validation, browser, search, repo-context, rca]
root_cause: "The authoritative UAT stack proved transport and attribution more strongly than semantic correctness, so verification-gate replies, stale /status content, and unexercised tool surfaces could still slip through as green."
---

# RCA: Authoritative Telegram UAT still had semantic false-green gaps for /status and exercised surfaces

## Summary

After the main Moltis runtime paths were repaired, authoritative Telegram UAT was already much better than plain transport checks, but it still had two blind spots:

1. an attributable `/status` reply could be treated as green even if it did not mention the canonical model or if it was actually a verification-gate reply;
2. the production UAT gate still proved provider/model health without explicitly exercising browser, search, and repo-context surfaces.

That meant a deploy could be transport-green and even attribution-green while still missing semantic confidence on the real operator path.

## Error

The UAT contract still answered “did we get a reply?” more reliably than “did we get the right reply from the right recovered runtime surface?”.

## 5 Whys

1. Why could `/status` still false-pass?
   Because the wrapper accepted the authoritative helper’s green verdict without checking whether the final `/status` text actually mentioned the canonical model.
2. Why was a verification-gate reply still risky?
   Because a direct verification-code prompt is not a transport error, so it could survive generic reply-quality checks unless it was treated as a semantic failure.
3. Why were browser/search/repo-context regressions still possible after a green canonical smoke?
   Because canonical smoke proved provider/model/restart survival, but not the exercised tool surfaces that had recently regressed in production.
4. Why did this remain after earlier UAT fixes?
   Because previous hardening focused on attribution and known error signatures first, not on message-specific semantic contracts and exercised-surface breadth.
5. Why is that dangerous operationally?
   Because operators use authoritative Telegram UAT and UAT gate outputs as rollout evidence; semantic false-green delays detection of real regressions.

## Root Cause

The authoritative UAT stack still lacked one final layer of semantic validation: message-specific `/status` contract checks and explicit exercised-surface coverage for browser, search, and repo-context.

## Fix

1. Hardened `scripts/telegram-e2e-on-demand.sh` so authoritative `/status` now fails if:
   - the reply is a verification-gate message;
   - the reply does not mention the canonical model `openai-codex::gpt-5.4`.
2. Added `scripts/moltis-exercised-surface-matrix.sh` to run deterministic browser/search/repo-context prompts through the canonical Moltis chat contract.
3. Updated `.github/workflows/uat-gate.yml` so post-deploy UAT now exercises:
   - browser -> `Introduction - Moltis Documentation`
   - search -> `docs.moltis.org`
   - repo-context -> `/server`
4. Added regression coverage for both the stricter Telegram semantics and the exercised-surface matrix.

## Verification

- `bash tests/component/test_telegram_remote_uat_contract.sh` -> `6/6 PASS`
- `bash tests/component/test_moltis_exercised_surface_matrix.sh` -> `1/1 PASS`
- `bash tests/static/test_config_validation.sh` -> `106/106 PASS`

## Preventive Actions

1. Keep authoritative `/status` tied to a canonical model string, not just a reply-presence check.
2. Treat verification-gate replies as failed authoritative outcomes on the allowlisted operator path.
3. Keep exercised-surface proof in UAT for any surface that previously regressed in production.
4. When new user-facing tool paths are added, extend the surface matrix instead of relying on generic smoke alone.
