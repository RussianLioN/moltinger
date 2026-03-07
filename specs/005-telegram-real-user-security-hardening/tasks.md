# Tasks: Telegram real_user Security Hardening

## Phase 1: Security Baseline

- [ ] T001 Define local secure-secret loading contract outside repo (`~/.config/moltinger/telegram-test.env`)
- [ ] T002 Document mandatory file permissions and shell loading guards (chmod 600 + strict sourcing)
- [ ] T003 Add operator checklist for zero-secret exposure in shell history and logs

## Phase 2: Secret Rotation & Recovery

- [ ] T010 Create repeatable rotation runbook for `TELEGRAM_TEST_API_ID/HASH/SESSION`
- [ ] T011 Add post-rotation verification flow (`real_user probe /status`) with expected outputs
- [ ] T012 Define break-glass recovery for compromised Telegram test account/session

## Phase 3: CI and Artifact Safety

- [ ] T020 Add CI validation step for redaction/no-secret-leak in telegram E2E logs/artifacts
- [ ] T021 Add regression check to ensure `telegram-e2e-result.json` never includes raw session material
- [ ] T022 Publish hardening summary and operator quick reference

