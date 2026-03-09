# Research: Codex CLI Update Advisor

## Inputs Reviewed

- `specs/007-codex-update-monitor/spec.md`
- `specs/007-codex-update-monitor/plan.md`
- `specs/007-codex-update-monitor/tasks.md`
- `docs/codex-cli-update-monitor.md`
- `scripts/codex-cli-update-monitor.sh`
- `tests/component/test_codex_cli_update_monitor.sh`
- `docs/CODEX-OPERATING-MODEL.md`
- `AGENTS.md`
- User-requested UX direction from the current session

## Decision 1: Build the advisor as a wrapper over the existing monitor

**Decision**: Reuse `scripts/codex-cli-update-monitor.sh` as the evidence collector and add a new advisor script that consumes its report.

**Rationale**:
- The monitor contract is already implemented, tested, and tied to `007`.
- Reusing it preserves a clean single source of truth for release evidence and repository relevance.
- A wrapper keeps the advisor focused on low-noise notification and project follow-up behavior.

**Alternatives considered**:
- Extend the monitor in place: rejected because it would blur the boundary between evidence collection and follow-up orchestration.
- Reimplement monitor logic inside the advisor: rejected because it would duplicate release parsing and relevance rules.

**Library**: No new library chosen. Existing shell tooling and the current monitor script cover the required behavior.

## Decision 2: Use a persisted state file for notification dedupe

**Decision**: Persist the last notified fingerprint in a small local state file.

**Rationale**:
- Duplicate suppression is the main user-value gap after `007`.
- A local state file works for on-demand runs, scheduled runs, and thin wrappers without adding infrastructure.
- The state file can degrade gracefully when missing or malformed.

**Alternatives considered**:
- No persisted state: rejected because every run would repeat the same alert.
- External database or webhook store: rejected because it adds infrastructure for a problem that is local in v1.

## Decision 3: Keep project change suggestions deterministic and path-aware

**Decision**: Generate suggestions from stable heuristics based on relevant change categories and known repository surfaces.

**Rationale**:
- The user wants plain-language guidance about what to change in this repository.
- Deterministic heuristics are easier to test and safer than free-form suggestion generation.
- Path-aware suggestions create a practical bridge from upstream changes to repo follow-up tasks.

**Alternatives considered**:
- Generic text-only recommendations: rejected because they still leave maintainers guessing which files or workflows are affected.
- LLM-generated suggestions in runtime: rejected because v1 should stay reproducible and fixture-testable.

## Decision 4: Beads remains the only tracked handoff sink in v1

**Decision**: If tracker sync is explicitly requested, create or update a Beads item with a richer implementation brief than the base monitor provides.

**Rationale**:
- Beads is the repository-standard tracked work surface.
- The advisor's job is to package follow-up work, not expand tracker support.
- This keeps mutation behavior aligned with the existing repo workflow.

**Alternatives considered**:
- Reuse only the monitor's issue sync: rejected because it does not include advisor-specific suggestions and brief structure.
- Add GitHub or Linear sinks in v1: rejected because they expand scope before the advisor UX proves itself.

## Decision 5: Keep scheduler and wrapper adoption easy

**Decision**: Preserve stable JSON output, support `--stdout json`, and allow the advisor to consume a precomputed monitor report.

**Rationale**:
- A future thin scheduler or skill should not need to reimplement monitor invocation or scrape prose.
- Consuming a precomputed monitor report enables CI or wrapper composition without changing advisor semantics.
- This matches the wrapper-ready principle already established in `007`.

**Alternatives considered**:
- Terminal-only summary mode: rejected because it blocks automation reuse.
- Scheduler-only state handling: rejected because manual local runs need the same behavior.

## Reusable Local Patterns

- `scripts/codex-cli-update-monitor.sh`: stable baseline evidence collector
- `tests/component/test_codex_cli_update_monitor.sh`: fixture-driven shell contract testing
- `docs/CODEX-OPERATING-MODEL.md`: source of impacted repository surfaces for Codex workflow changes
- `AGENTS.md`: source of boundary and process suggestions likely to change after Codex upgrades

## Planning Notes

- V1 notification surfaces are summary output plus optional Beads handoff, not OS notifications, chat webhooks, or long-running daemons.
- Suggestion mapping should prefer concrete repo paths over generic prose.
- `investigate` results should be conservative and may intentionally produce fewer concrete change suggestions.
- The advisor should remain valuable even when the underlying monitor report is supplied externally.

## Implementation Preflight (2026-03-09)

- Verified the base monitor entrypoint exists at `scripts/codex-cli-update-monitor.sh` and already emits the stable fields the advisor will consume.
- Verified this worktree resolves the shared Beads database through `.beads/redirect`, so explicit local tracker sync remains available without adding a second tracker backend.
- Chosen default advisor state location: `.tmp/current/codex-cli-update-advisor-state.json`, with an explicit `--state-file` override for repeatable tests and wrappers.
- Confirmed the v1 advisor can stay library-free: the existing shell toolchain, `jq`, `python3`, and optional `bd` are sufficient.
