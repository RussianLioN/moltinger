# Feature Specification: Telegram real_user Security Hardening

## Summary

Harden the newly enabled Telegram `real_user` E2E flow so daily testing can continue safely without exposing account/session secrets.

## Problem

Current flow works end-to-end, but operational security tasks remain open:
- no scheduled secret/session rotation policy
- no finalized local secure-secret loading convention
- no explicit guardrails for CI/log redaction verification
- no formal break-glass/recovery playbook for compromised test account

## Goals

1. Keep real_user testing fast and reliable.
2. Reduce blast radius if test credentials leak.
3. Make operator workflow reproducible across sessions.

## Non-Goals

1. Replacing MTProto transport.
2. Adding autonomous mass messaging behavior.
3. Changing production bot DM policy semantics.

## User Stories

### US1: Secure local operator bootstrap
As an operator, I can bootstrap and run real_user probes using a secure local secret file outside the repo.

### US2: Secret/session lifecycle
As an operator, I can rotate `TELEGRAM_TEST_*` secrets and session on a repeatable cadence.

### US3: Safe observability
As an operator, I can verify that logs/artifacts never expose raw secret values.

## Success Criteria

1. Operator can run real_user probe without manually re-entering API credentials each session.
2. Rotation playbook can be executed in under 15 minutes.
3. Security checks confirm no raw `TELEGRAM_TEST_SESSION` leakage in logs/artifacts.

