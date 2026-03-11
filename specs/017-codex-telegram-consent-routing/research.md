# Research: Codex Telegram Consent Routing

## Inputs Reviewed

- `specs/012-codex-upstream-watcher/spec.md`
- `docs/codex-cli-upstream-watcher.md`
- `scripts/codex-cli-upstream-watcher.sh`
- `config/moltis.toml`
- `docs/telegram-e2e-on-demand.md`
- `scripts/telegram-e2e-on-demand.sh`
- `scripts/telegram-real-user-e2e.py`
- `docs/telegram-webhook-rollout.md`
- `docs/research/telegram-bot-testing-strategies.md`
- Consilium findings from the current session

## Decision 1: The main Moltis Telegram ingress is the authoritative owner of consent replies

**Decision**: The production path for `yes/no` follow-up decisions must run through the main Moltis Telegram ingress instead of watcher-side polling.

**Rationale**:
- The current failure happened because the watcher asked the question but the main bot received the reply.
- One inbound owner is easier to reason about, test, and operate.
- This works whether the bot remains in polling mode or moves to webhook mode later.

**Alternatives considered**:
- Keep watcher-side `getUpdates` in production: rejected because it creates a second consumer for the same update stream.
- Use a dedicated sidecar that races the main bot for updates: rejected because it preserves the ownership problem.

## Decision 2: Inline callback actions are the primary UX

**Decision**: The preferred user-facing control is an explicit inline action pair such as `Получить рекомендации` / `Не нужно`.

**Rationale**:
- Buttons remove ambiguity from free-text `да/нет`.
- Callback payloads can carry a compact correlation id for exact matching.
- The bot can treat a callback as a special consent interaction instead of a generic chat turn.

**Alternatives considered**:
- Keep free-text `да/нет`: rejected because it is too easy for the generic bot dialog to consume it as a normal prompt.
- Force operators to run a local CLI command after each alert: rejected because it breaks the intended Telegram UX.

## Decision 3: Keep a tokenized text fallback for constrained clients

**Decision**: Provide a fallback command such as `/codex-followup yes <token>` when inline callback actions are unavailable.

**Rationale**:
- Some Telegram clients, relays, or degraded channels may not support inline interactions cleanly.
- A tokenized command still gives explicit correlation and avoids ambiguous free text.

**Alternatives considered**:
- Support only inline actions: rejected because it leaves no degraded path.
- Support arbitrary text replies without a token: rejected because it reintroduces the same ambiguity.

## Decision 4: Use a shared consent store outside watcher-local state

**Decision**: Store consent requests and decisions in one authoritative machine-readable store that both the watcher and the main ingress can understand.

**Rationale**:
- The current watcher-local pending state cannot be authoritative if the main bot handles the reply.
- A shared store gives auditability, deduplication, expiry handling, and deterministic retries.

**Alternatives considered**:
- Keep storing pending consent only in the watcher state file: rejected because the main ingress cannot safely own the reply.
- Push everything into transient chat context only: rejected because operators need auditability and replay-safe state.

## Decision 5: Acceptance should trigger immediate follow-up, not another scheduler wait

**Decision**: After a valid `accept`, the practical recommendations should be sent from the authoritative runtime path immediately.

**Rationale**:
- Waiting for the next cron run makes the UX laggy and brittle.
- Immediate delivery also makes live acceptance tests deterministic.

**Alternatives considered**:
- Accept now, send on next scheduler run: rejected because that is exactly the fragile pattern that confused the live UX.

## Decision 6: MTProto remains a validation tool, not the production ingress

**Decision**: MTProto/`real_user` sessions stay limited to E2E validation and must not become the main production consent-routing mechanism.

**Rationale**:
- The repository already treats `real_user` as a test harness.
- MTProto adds more sensitive secrets and session lifecycle complexity.
- It does not solve the core ownership problem by itself.

**Alternatives considered**:
- Use a production userbot/service user for the consent flow: rejected because it is operationally heavier and still not the authoritative bot ingress.

## Decision 7: Fail safe to one-way alerts when consent routing is unhealthy

**Decision**: If the authoritative consent router is unavailable or disabled, the watcher should send a one-way alert only and stop advertising a broken interactive follow-up.

**Rationale**:
- A truthful one-way alert is better than a misleading prompt that cannot be honored.
- This gives a clean rollback mode during rollout or incidents.

**Alternatives considered**:
- Keep showing the consent question even when routing is unhealthy: rejected because it recreates the exact user-facing failure.

## Reusable Local Patterns

- `config/moltis.toml`: authoritative Telegram runtime configuration surface
- `scripts/codex-cli-upstream-watcher.sh`: producer of alert content and recommendation payloads
- `scripts/telegram-bot-send.sh`: Telegram outbound primitive
- `scripts/telegram-e2e-on-demand.sh`: existing synthetic/real-user acceptance harness
- `scripts/telegram-real-user-e2e.py`: live user-path verification tool

## Planning Notes

- This feature exists because the current interactive Telegram promise is stronger than the real architecture behind it.
- The new feature should not be framed as “webhook vs MTProto”; the real issue is authoritative ownership of inbound consent.
- Callback-first UX plus shared consent state is the cleanest target architecture.
- The rollout should include a one-way alert fallback mode and a live E2E acceptance scenario.
