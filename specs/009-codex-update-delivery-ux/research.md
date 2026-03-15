# Research: Codex Update Delivery UX

## Inputs Reviewed

- `specs/008-codex-update-advisor/spec.md`
- `docs/codex-cli-update-advisor.md`
- `scripts/codex-cli-update-advisor.sh`
- `scripts/codex-profile-launch.sh`
- `scripts/telegram-bot-send.sh`
- `.claude/commands/worktree.md`
- `AGENTS.md`
- User-requested UX direction from the current session

## Decision 1: Keep the advisor as the recommendation source of truth

**Decision**: The delivery layer will consume the advisor output and will not compute recommendations on its own.

**Rationale**:
- `008` already encapsulates recommendation, noise control, and repository suggestion logic.
- Splitting recommendation and delivery keeps behavior testable and avoids drift.
- The user asked for better UX, not a second engine.

**Alternatives considered**:
- Recompute recommendation inside the delivery layer: rejected because it duplicates business logic and creates drift risk.
- Merge delivery directly into the advisor: rejected because it would blur the boundary between decision and transport.

**Library**: No new library chosen. Existing shell tooling and advisor runtime are sufficient.

## Decision 2: Make the Codex-facing UX a wrapper, not a raw script contract

**Decision**: Provide a Codex-facing command or skill surface that runs the delivery script and returns a plain-language result.

**Rationale**:
- The user explicitly asked not to remember script flags.
- The repository already uses `.claude/commands/` and skills as human-facing entry surfaces.
- A wrapper can keep the runtime contract stable while giving users a short natural-language path.

**Alternatives considered**:
- Document scripts only: rejected because it preserves the current UX gap.
- Build a separate agent daemon first: rejected because a wrapper is the shorter path to useful UX.

## Decision 3: Put Codex-side visibility at launcher startup

**Decision**: Show Codex update delivery alerts in `scripts/codex-profile-launch.sh` before entering Codex.

**Rationale**:
- Startup is the simplest reliable point to show an alert to an active CLI user.
- It avoids trying to inject asynchronous notifications into an already running Codex TUI.
- It matches the user's desire to see update awareness when starting work.

**Alternatives considered**:
- In-session pop-up during an already running Codex session: rejected for v1 because it is less predictable and not supported by current repo runtime patterns.
- No startup alert: rejected because it misses the most practical Codex-facing surface.

## Decision 4: Reuse the existing Telegram bot send path

**Decision**: Use `scripts/telegram-bot-send.sh` as the Telegram transport primitive.

**Rationale**:
- The repository already has a working Telegram bot send path.
- Reusing it avoids creating a second Telegram integration path.
- This keeps the new feature focused on delivery state and message composition.

**Alternatives considered**:
- Direct Moltinger-specific transport implementation: rejected because the existing sender already solves the transport problem.
- Webhook-only custom notification stack: rejected because it expands scope unnecessarily.

## Decision 5: Share delivery state across surfaces

**Decision**: Use one delivery state model with per-surface results.

**Rationale**:
- Without shared state, on-demand reports, launcher alerts, and Telegram sends would spam independently.
- Per-surface state allows one surface to succeed while another remains retryable.
- It preserves explicit auditability for delivery failures.

**Alternatives considered**:
- Independent state per surface with no coordination: rejected because it would create noisy and contradictory UX.
- One global delivered flag with no per-surface detail: rejected because it hides partial failures.

## Decision 6: Prefer launcher-triggered automation over server-side scheduling

**Decision**: Use the local Codex launcher as the primary automation point and delegate Telegram transport to the Moltinger server only when local bot secrets are unavailable.

**Rationale**:
- The Codex CLI being monitored lives on the user's machine, not on the Moltinger host.
- The Moltinger host currently does not have `codex` installed, so a host cron job would monitor the wrong runtime.
- Reusing the server-side bot token over SSH keeps Telegram delivery automatic without requiring the local machine to store Telegram bot secrets.

**Alternatives considered**:
- Host cron on Moltinger: rejected for v1 because it lacks the local Codex runtime being monitored.
- GitHub Actions schedule: rejected for v1 because CI would observe CI's Codex environment, not the operator's local CLI state.
- Requiring a local bot token on every machine: rejected because the bot is already configured centrally in the Moltinger runtime.

## Reusable Local Patterns

- `scripts/codex-cli-update-advisor.sh`: baseline source of recommendation and suggestion truth
- `scripts/codex-profile-launch.sh`: repo-standard Codex entrypoint
- `scripts/telegram-bot-send.sh`: existing Telegram transport path
- `scripts/telegram-bot-send-remote.sh`: launcher-safe bridge to the existing Moltinger Telegram runtime
- `.claude/commands/worktree.md`: example of human-facing repo command UX

## Planning Notes

- V1 explicitly supports on-demand text UX, launch-time alerting, and Telegram delivery.
- Telegram delivery should stay opt-in and configuration-driven.
- Launch-time delivery must never prevent Codex from starting.
- Future schedulers can be layered on top once the delivery runtime exists, but startup automation is the reliable primary path in v1.
