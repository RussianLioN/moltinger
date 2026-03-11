# Specification Quality Checklist: Codex Telegram Consent Routing

**Feature**: `017-codex-telegram-consent-routing`

## Completeness

- [x] Problem statement is tied to the observed live Telegram failure.
- [x] User stories cover authoritative routing, immediate follow-up, and safe fallback.
- [x] Requirements distinguish production ingress from E2E-only MTProto usage.
- [x] Success criteria are measurable.

## Clarity

- [x] The feature states one authoritative owner for inbound consent.
- [x] The difference between inline actions and fallback command is explicit.
- [x] Degraded one-way alert behavior is specified.

## Testability

- [x] Independent tests exist for each user story.
- [x] Live acceptance is required in addition to fixture coverage.
- [x] Machine-readable consent records are part of the contract.
