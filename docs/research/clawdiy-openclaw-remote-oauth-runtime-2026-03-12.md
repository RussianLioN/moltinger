# Clawdiy / OpenClaw Remote Runtime OAuth Research

**Date**: 2026-03-12  
**Status**: Research complete, planning handoff ready  
**Scope**: Production-grade `codex-oauth` / `gpt-5.4` lifecycle for Clawdiy when OpenClaw runs in a container on remote VDS `ainetic.tech`

**Breadcrumbs**: [Docs](/Users/rl/coding/moltinger-openclaw-control-plane/docs) / [Research](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/README.md) / `clawdiy-openclaw-remote-oauth-runtime-2026-03-12`

**Related artifacts**:
- [docs/research/clawdiy-openclaw-browser-bootstrap-2026-03-12.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-browser-bootstrap-2026-03-12.md)
- [docs/runbooks/clawdiy-browser-bootstrap.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-browser-bootstrap.md)
- [specs/001-clawdiy-agent-platform/research.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/001-clawdiy-agent-platform/research.md)
- [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md)
- [docs/SECRETS-MANAGEMENT.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/SECRETS-MANAGEMENT.md)
- [config/clawdiy/openclaw.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/clawdiy/openclaw.json)
- [specs/017-clawdiy-remote-oauth-lifecycle/spec.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/spec.md)

## Executive Summary

Current Clawdiy production docs and config model `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` only as rollout metadata. That is enough to gate policy and smoke checks, but not enough to establish a real OpenClaw runtime OAuth session for `codex-oauth` with `gpt-5.4`.

Fresh official documentation still recommends the remote SSH/VPS paste-back flow, and the Docker install docs explicitly describe headless Codex OAuth as a CLI/wizard path that captures a redirect on `http://127.0.0.1:1455/...`. Separate official browser docs show that hosted dashboard bootstrap is its own layer: browser token state plus device pairing. The most practical near-term path is to bootstrap browser access first, then run the official CLI/wizard OAuth flow against the actual target runtime auth store, then keep metadata, verification, and quarantine logic under GitOps. The cleaner target-state is to treat the runtime auth artifact as a first-class deployment asset with version-matched bootstrap and explicit delivery lifecycle.

## Repo-Local Gap Audit

The repository already contains useful but incomplete Clawdiy OAuth artifacts:

- [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md) describes repeat-auth at the metadata level, not the real runtime auth store.
- [docs/SECRETS-MANAGEMENT.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/SECRETS-MANAGEMENT.md) reserves `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE`, but does not define how a real `auth-profiles.json` is created, delivered, rotated, or validated.
- [config/clawdiy/openclaw.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/clawdiy/openclaw.json) does not yet carry an explicit long-lived contract for runtime auth store placement plus `models.providers.codex-oauth` activation.
- [specs/001-clawdiy-agent-platform/research.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/001-clawdiy-agent-platform/research.md) correctly identified `codex-oauth` instability, but did not finish the production lifecycle design for remote container runtime auth.

Conclusion: the repo needs a dedicated follow-on implementation track for real runtime OAuth lifecycle, not only metadata gating.

## Official Evidence

| Source | Checked | Official evidence | Impact |
|---|---|---|---|
| https://docs.openclaw.ai/web/dashboard | 2026-03-12 | Hosted control starts from dashboard connection parameters entered client-side. | Clawdiy docs must distinguish browser bootstrap from provider OAuth. |
| https://docs.openclaw.ai/web/control-ui | 2026-03-12 | New browser profiles behave like new devices and need browser-local state. | Fresh browser bootstrap and device pairing are normal hosted UI steps, not evidence of broken deploy. |
| https://docs.openclaw.ai/cli/devices | 2026-03-12 | Pending browser devices must be approved through the device flow. | Hosted browser bootstrap needs pairing approval before provider auth is even relevant. |
| https://docs.openclaw.ai/install/docker | 2026-03-12 | The Docker install page includes a headless Codex OAuth section that explicitly describes a wizard/CLI flow with callback URL paste-back. | Browser UI must not be documented as the canonical Codex OAuth path. |
| https://docs.openclaw.ai/start/auth/codex-oauth | 2026-03-12 | Official flow for `codex-oauth` uses `openclaw models auth login --provider codex-oauth --set-default`. | Runtime auth is a model/provider login flow, not merely an env flag. |
| https://docs.openclaw.ai/help/faq#i-am-using-ssh-remote-terminal-or-vps-and-codex-oauth-auth-opens-a-localhost-url-that-does-not-work-how-do-i-finish-login | 2026-03-12 | Official FAQ for remote/VPS says: open the URL locally, allow redirect to `http://localhost:1455/...`, then copy the full callback URL back to the remote terminal. | Remote container login is officially supported, but relies on a manual paste-back loop. |
| https://docs.openclaw.ai/concepts/model-failover | 2026-03-12 | OpenClaw documents model/provider state and auth-profile behavior as runtime concepts. | Real runtime provider auth must be treated as persistent state, not only deployment metadata. |
| https://github.com/openclaw/openclaw | 2026-03-12 | Official upstream repository for current OpenClaw releases; npm metadata reports version `2026.3.11`. | The implementation should stay aligned to actual upstream release behavior, not older Moltis assumptions. |

## Community Evidence

Community evidence below is restricted to official OpenClaw GitHub issues because they are fresher and more operationally relevant than secondary blog/forum summaries.

| Source | Checked | Community signal | Impact |
|---|---|---|---|
| https://github.com/openclaw/openclaw/issues/41885 | 2026-03-12 | Remote/VPS OAuth can hang even after pasting the callback URL back into the SSH flow. | The official remote paste-back path is currently unreliable in some builds. |
| https://github.com/openclaw/openclaw/issues/42291 | 2026-03-12 | OAuth login on one host can write token state locally instead of syncing it to the intended runtime/gateway. | Auth locality must be explicit; writing the token into the wrong store is a real failure mode. |
| https://github.com/openclaw/openclaw/issues/40364 | 2026-03-12 | Even with a valid OAuth profile present, the Codex provider may not become active in `models.json` without explicit provider wiring. | Runtime activation needs an explicit `models.providers.codex-oauth` contract. |
| https://github.com/openclaw/openclaw/issues/26538 | 2026-03-12 | Users are asking for first-class gateway RPC auth because the current CLI/TTY path is brittle. | The current UX is known upstream to be awkward and not ideal for long-lived remote runtimes. |
| https://github.com/openclaw/openclaw/issues/39994 | 2026-03-12 | OAuth may look successful while still missing required scopes such as `api.responses.write`. | Post-auth verification must test scopes and fail closed before the provider is promoted. |

## Explicit Inference

The following points are inference, not direct quotes:

- A Clawdiy production rollout cannot claim `gpt-5.4` readiness until the runtime auth store exists on the target container and a real upstream execution path succeeds.
- `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` should remain as metadata gate and policy evidence, but it must not be mistaken for the runtime credential artifact itself.
- A production-grade flow needs three separate objects:
  - metadata gate in GitHub Secrets and CI rendering;
  - browser bootstrap state for hosted dashboard access;
  - runtime auth store used by OpenClaw itself;
  - post-auth canary evidence proving `gpt-5.4` actually executes.
- Hosted browser bootstrap must not be documented as a provider-auth wizard unless the live build actually surfaces that UI.
- Because remote paste-back is brittle and auth locality is failure-prone, the chosen design should optimize first for writing auth into the correct runtime store, then for minimizing operator friction.

## Compared OAuth Approaches

### Method 1: Official remote paste-back inside the live container

Description:
- Run `openclaw models auth login --provider codex-oauth --set-default` inside the live Clawdiy runtime.
- User opens the issued URL locally.
- User copies the `http://localhost:1455/...` callback URL and pastes it back into the remote terminal.

Pros:
- Fully aligned with official docs.
- No extra bootstrap environment required.

Cons:
- Fresh upstream evidence shows current hangs and brittle callback completion.
- Easy to write auth into the wrong locality if runtime/store paths are not explicit.
- Hard to standardize in GitOps because the result exists outside the normal deploy artifact lifecycle.

### Method 2: Bootstrap against the actual target runtime auth store, then keep verification under GitOps

Description:
- Create or mount the exact runtime auth store used by live Clawdiy.
- Execute OAuth against that real target store, not a metadata placeholder.
- Keep deploy workflow, auth-check, quarantine, and canary evidence in repo-controlled automation.

Pros:
- Solves the auth locality problem directly.
- Best practical fit for the current repo because Clawdiy is already live on `ainetic.tech`.
- Lets GitOps continue to own metadata, verification, and rollout state even if the token artifact itself is not stored in git.

Cons:
- Still depends on a brittle operator bootstrap flow for the first login.
- Requires explicit documentation of runtime store paths and ownership.

### Method 3: Version-matched trusted-workstation bootstrap, then deliver the auth artifact into the runtime store

Description:
- Run a local OpenClaw environment with the same version/image as production.
- Complete OAuth locally where `localhost:1455` works naturally.
- Export the resulting auth artifact and deliver it into the live runtime store under a controlled operator procedure.

Pros:
- Avoids the remote paste-back instability entirely.
- Can be made highly repeatable once the artifact lifecycle is formalized.
- Cleanest long-term shape for GitOps-compatible operator runbooks.

Cons:
- The repo does not yet have a first-class artifact-delivery lifecycle for runtime auth state.
- Requires careful version parity and secure artifact handling.

## Consilium Scoring

Scale: `1-10`, higher is better.

| Method | Reliability | Operator friction | Security boundary | GitOps fit | Elegance | Total |
|---|---:|---:|---:|---:|---:|---:|
| 1. Official remote paste-back | 3 | 6 | 7 | 3 | 4 | 23 |
| 2. Bootstrap on actual target runtime store | 8 | 6 | 7 | 8 | 7 | 36 |
| 3. Version-matched workstation bootstrap + artifact delivery | 9 | 7 | 8 | 9 | 8 | 41 |

Independent expert synthesis:
- SRE line preferred method `3`.
- Architect line also viewed method `3` as the cleanest target-state, but warned that the repo currently lacks a formal runtime auth artifact lifecycle.
- GitOps line preferred method `2` as the best practical-now solution because it avoids locality drift on the live target while preserving CI-managed verification and quarantine.

## Consolidated Recommendation

Recommended for immediate implementation: **Method 2**

Reason:
- It best fits the current reality that Clawdiy already runs on `ainetic.tech`.
- It addresses the auth-locality problem documented in `#42291`.
- It avoids pretending that metadata-only env state is sufficient.
- It can be implemented without waiting for upstream gateway-auth improvements.

Recommended target-state after the first implementation: **Method 3**

Reason:
- It is the cleanest long-term operator experience.
- It minimizes dependence on fragile remote paste-back.
- It turns runtime OAuth into a more explicit and portable lifecycle that can later support other permanent agents.

## Required Follow-On Changes

The next implementation track should update or extend all of the following:

- [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md)
  - Add real runtime auth store lifecycle, not only metadata gate checks.
- [docs/SECRETS-MANAGEMENT.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/SECRETS-MANAGEMENT.md)
  - Separate metadata secrets from runtime auth artifact handling.
- [config/clawdiy/openclaw.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/clawdiy/openclaw.json)
  - Add explicit runtime provider activation requirements for `codex-oauth`.
- `deploy-clawdiy.yml`, `scripts/clawdiy-auth-check.sh`, `scripts/clawdiy-smoke.sh`, and regression tests
  - Upgrade from metadata-only gate validation to runtime-store presence plus post-auth canary evidence.
- [specs/017-clawdiy-remote-oauth-lifecycle/spec.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/spec.md)
  - Track the actual implementation plan and acceptance contract.

## Recommended Operator Principles

1. Never treat `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` as proof that OpenClaw is actually authenticated.
2. Never declare `gpt-5.4` ready until a real upstream canary succeeds.
3. Keep runtime auth artifacts out of git, but keep their lifecycle, ownership, and verification under GitOps-controlled docs and automation.
4. Separate baseline Clawdiy health from optional `codex-oauth` capability so failures quarantine the provider without taking down the agent.
5. Prefer writing auth once into the correct runtime store over “successful” login into the wrong locality.

## See Also

- [docs/research/README.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/README.md)
- [docs/INFRASTRUCTURE.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/INFRASTRUCTURE.md)
- [docs/deployment-strategy.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/deployment-strategy.md)
