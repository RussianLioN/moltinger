# Implementation Plan: Telegram real_user Security Hardening

## Scope

Formalize secure operational controls around existing real_user MTProto testing.

## Deliverables

1. Security runbook for local secret handling (`~/.config/moltinger/telegram-test.env`).
2. Rotation procedure for Telegram test API/session credentials.
3. CI/log redaction validation checklist and verification command set.
4. Incident recovery procedure for test-account compromise.

## Constraints

1. No plaintext secrets in repository.
2. No changes that degrade current real_user E2E functionality.
3. Preserve manual-approval and human-in-the-loop safety.

## Validation

1. Run redaction checks against local logs and workflow artifacts.
2. Execute one full rotation dry-run in staging/production workflow path.
3. Re-run real_user probe after rotation and confirm `status=completed`.

