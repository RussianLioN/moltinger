# Research: Codex CLI Update Monitor

## Inputs Reviewed

- `docs/plans/codex-cli-update-monitoring-speckit-seed.md`
- `docs/research/codex-cli-update-monitoring-2026-03-09.md`
- `scripts/telegram-webhook-monitor.sh`
- `scripts/health-monitor.sh`
- `docs/CODEX-OPERATING-MODEL.md`
- `scripts/codex-profile-launch.sh`

## Decision 1: Use a script-first monitor

**Decision**: Build v1 as a deterministic shell workflow centered on one monitor script.

**Rationale**:
- Matches existing repository operational patterns.
- Easier to test and validate than a long-running agent.
- Produces a clear source of truth for JSON and summary contracts.

**Alternatives considered**:
- Agent-first monitor: rejected because it is harder to reproduce, diff, and validate.
- Plugin-first packaging: rejected because reuse is desirable but not the shortest path to value.
- Background daemon: rejected because v1 needs explicit, on-demand runs rather than constant polling.

**Library**: No new library chosen. Existing shell toolchain plus `codex`, `curl`, and `jq` is sufficient for v1.

## Decision 2: Make official Codex releases the primary evidence source

**Decision**: Base the recommendation primarily on official Codex release information and only layer issue signals as secondary evidence.

**Rationale**:
- Official releases are the most defensible signal for upgrade decisions.
- Issue activity can indicate risk or urgency, but it is too noisy to act as the sole trigger.
- This aligns with the seed requirement that remote issue activity alone must not force an upgrade.

**Alternatives considered**:
- Issue feeds only: rejected because it can overreact to transient or low-signal discussions.
- Release notes only with no issue option: rejected because selected issue signals may still help identify regressions or upgrade risk.

## Decision 3: Support both local and CI-safe manual entrypoints in v1

**Decision**: Design the monitor so the same contract can be run locally and from a manual GitHub workflow.

**Rationale**:
- Operators need a quick local command during a Codex session.
- The same workflow should be invokable from CI/manual automation without changing semantics.
- Seed scope explicitly called out on-demand local runs and CI/manual automation as the desired direction.

**Alternatives considered**:
- Local-only v1: rejected because it delays a likely workflow consumer.
- CI-only v1: rejected because local operator usage is the primary fast-feedback path.

## Decision 4: Keep Beads as the only tracker sink in v1

**Decision**: If tracker sync is requested, create or update Beads work only.

**Rationale**:
- Beads is the repository-standard issue system.
- Adding more sinks now would complicate the contract without immediate value.
- The design can still preserve an abstract issue-action block for future expansion.

**Alternatives considered**:
- GitHub Issues or Linear in v1: rejected because they would add another workflow surface before the core monitor proves itself.
- No tracker integration at all: rejected because the seed explicitly called for optional tracked follow-up.

## Decision 5: Preserve wrapper-friendly output contracts

**Decision**: Separate machine-readable report output from the human summary and keep error states structured.

**Rationale**:
- Future skills or wrappers should not scrape narrative stdout.
- Stable contracts reduce rework if the monitor later becomes a skill or plugin.
- This mirrors the repo's preference for deterministic script interfaces.

**Alternatives considered**:
- Single prose-only output: rejected because it is fragile for automation.
- Wrapper implemented before contract stabilizes: rejected because it couples reuse to an unstable v1.

## Relevant Upstream Findings Carried Into Planning

- `0.112.0` adds approval-profile and prompt/plugin improvements, but only approval-profile behavior appears moderately relevant to this repository.
- `0.111.0` adds worktree, `js_repl`, resume, and `.gitignore` safety improvements, several of which are high or medium relevance here.
- `0.110.0` improves multi-agent behavior and no-restart doc refresh, both of which are materially useful for this repository's operating model.

## Reusable Local Patterns

- `scripts/health-monitor.sh`: deterministic monitor/report flow
- `scripts/telegram-webhook-monitor.sh`: operational shell script with reporting and safe failure paths
- `scripts/codex-profile-launch.sh`: Codex-specific local runtime context
- `docs/plans/codex-rollout-rollback.md`: durable operational guidance for Codex-related work

## Planning Notes

- The feature package assumes v1 will read local Codex state, fetch upstream release data, classify relevance, and optionally sync a Beads issue.
- No runtime code or workflow should self-upgrade Codex.
- The monitor should emit both JSON and Markdown outputs even when recommendations are non-actionable, so runs remain comparable over time.
