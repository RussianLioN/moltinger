# Quickstart: Codex CLI Update Advisor

## Goal

Validate that the advisor can wrap the existing monitor, suppress duplicate alerts, suggest concrete repository follow-up work, and optionally create or update a Beads implementation brief.

## First Run With Local Monitor Invocation

```bash
./scripts/codex-cli-update-advisor.sh \
  --release-file tests/fixtures/codex-update-monitor/releases.json \
  --config-file tests/fixtures/codex-update-monitor/config.toml \
  --local-version 0.110.0 \
  --state-file .tmp/current/codex-update-advisor-state.json \
  --json-out .tmp/current/codex-update-advisor-report.json \
  --summary-out .tmp/current/codex-update-advisor-summary.md
```

Expected result:
- Advisor emits JSON and Markdown outputs
- Notification status is `notify`
- Report includes one or more project change suggestions
- State file is created or updated

## Repeat Run With The Same State

Run the same command again.

Expected result:
- Advisor still emits JSON and Markdown outputs
- Notification status becomes `suppressed`
- Summary explains that the actionable state was already seen
- Suggestions remain available for reference, but no new alert is raised

## Run From A Precomputed Monitor Report

```bash
./scripts/codex-cli-update-advisor.sh \
  --monitor-report tests/fixtures/codex-update-advisor/monitor-upgrade-now.json \
  --state-file .tmp/current/codex-update-advisor-state.json \
  --stdout json
```

Expected result:
- Advisor does not need to fetch upstream sources directly
- JSON contract includes `monitor_snapshot`, `notification`, `project_change_suggestions`, `implementation_brief`, and `issue_action`

## Explicit Beads Handoff

```bash
./scripts/codex-cli-update-advisor.sh \
  --monitor-report tests/fixtures/codex-update-advisor/monitor-upgrade-now.json \
  --state-file .tmp/current/codex-update-advisor-state.json \
  --issue-action upsert \
  --beads-db /Users/rl/coding/moltinger/.beads/beads.db
```

Expected result:
- Default read-only behavior changes only because explicit sync was requested
- If the notification result is above threshold, the advisor creates or updates a Beads item
- The issue action records `created`, `updated`, or `skipped` with notes

## Verification Checklist

1. Confirm the summary says whether the result is new, repeated, silent, or needs investigation.
2. Confirm suggestions reference concrete repository paths or explicitly explain why they cannot.
3. Confirm repeated identical runs do not emit a fresh notify decision.
4. Confirm explicit tracker sync remains opt-in and auditable.

## Make Target

```bash
make codex-update-advisor
```

Expected result:
- Advisor writes `.tmp/current/codex-update-advisor-report.json`
- Advisor writes `.tmp/current/codex-update-advisor-summary.md`
- Advisor writes `.tmp/current/codex-cli-update-advisor-state.json` when the run is fresh and actionable
