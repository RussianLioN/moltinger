# Research: Production-Aware Remote UAT Hardening

## Decision 1: Telegram Web remains the authoritative production-aware live path

- **Decision**: Use Telegram Web as the canonical post-deploy remote UAT path for production-aware verification.
- **Rationale**: The operator question is whether the deployed service works now through the real Telegram user path. The repo already has a Telegram Web probe, login flow, correlation tests, and manual runbooks that match this operational intent.
- **Alternatives considered**:
  - Make MTProto the authoritative path: rejected because the production server currently lacks `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`, and the feature scope explicitly keeps MTProto optional for MVP.
  - Treat webhook or Bot API transport as authoritative: rejected because production intentionally remains on polling and webhook migration is out of scope.
- **Library/Platform**: Reuse existing Playwright-based Telegram Web automation already present in the repo.

## Decision 2: Harden the existing Telegram Web probe instead of creating a second remote-UAT stack

- **Decision**: Extend the existing Telegram Web probe, monitor wrapper, live test coverage, and on-demand UAT surfaces.
- **Rationale**: The current repo already contains staged Telegram Web failures, correlation metadata, and operator-facing docs. Hardening these surfaces preserves one source of truth and avoids parallel artifact formats.
- **Alternatives considered**:
  - Build a brand-new remote-UAT script or workflow: rejected because it would duplicate trigger, artifact, and diagnostic logic that already exists in `telegram-web-user-probe.mjs` and related wrappers.
  - Depend only on the older MTProto monitor: rejected because it does not satisfy the requirement that Telegram Web is the primary authoritative path.

## Decision 3: Formalize a deterministic failure taxonomy from current staged behavior

- **Decision**: Normalize authoritative failure results into a stable set of diagnostic classes aligned with the operator-facing categories in the feature spec.
- **Rationale**: The current probe already reports execution stages and correlation context, but the operational value is limited unless those outcomes are stabilized into explicit failure classes such as send failure, UI drift, stale chat noise, missing session state, chat-open failure, and bot no-response.
- **Alternatives considered**:
  - Keep generic timeout or fail statuses only: rejected because they do not narrow the root cause enough for post-deploy operations or RCA.
  - Encode only free-form log text: rejected because it is less reliable for tooling and harder to compare across reruns.

## Decision 4: Preserve manual/on-demand execution and keep blocking CI hermetic-only

- **Decision**: Maintain remote UAT as a manual, opt-in post-deploy verification path and keep PR/main blocking gates limited to hermetic lanes.
- **Rationale**: Repo policy and existing docs already distinguish hermetic correctness checks from remote “does production work now?” validation. Production deploy automation also disables the Telegram Web scheduler by default.
- **Alternatives considered**:
  - Promote remote UAT to a blocking PR or main gate: rejected because shared production-aware checks are not suitable as the primary proof of branch correctness.
  - Re-enable periodic Telegram Web monitoring by default: rejected because it would reintroduce continuous production traffic and violate the current operational boundary.

## Decision 5: Keep MTProto as optional secondary diagnostics until the primary path is resolved

- **Decision**: Treat MTProto as an optional fallback or diagnostic lane, and defer any production enablement decision until after the Telegram Web path is fixed or narrowed to root cause.
- **Rationale**: Current production defaults and documented secrets policy do not require MTProto for the manual authoritative check. A secondary lane may still be useful later to distinguish product issues from Telegram Web automation issues, but it must not replace the primary verdict.
- **Alternatives considered**:
  - Require MTProto fallback for MVP: rejected because it would expand scope and conflict with current production prerequisites.
  - Remove fallback consideration entirely: rejected because the team still needs a disciplined post-fix decision point on whether additional diagnostics remain justified.
