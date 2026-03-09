# Quickstart: Codex CLI Update Monitor

## Goal

Validate that an operator can run the monitor locally or from a manual workflow, receive stable JSON and Markdown outputs, and optionally request a Beads follow-up when the recommendation warrants action.

## Local Run

```bash
./scripts/codex-cli-update-monitor.sh \
  --json-out .tmp/current/codex-update-report.json \
  --summary-out .tmp/current/codex-update-summary.md
```

Expected result:

- JSON report written to `.tmp/current/codex-update-report.json`
- Markdown summary written to `.tmp/current/codex-update-summary.md`
- Recommendation is one of `upgrade-now`, `upgrade-later`, `ignore`, or `investigate`

## Local Run With Advisory Issue Signals

```bash
./scripts/codex-cli-update-monitor.sh \
  --include-issue-signals \
  --json-out .tmp/current/codex-update-report.json \
  --summary-out .tmp/current/codex-update-summary.md
```

Expected result:

- Baseline recommendation still works even if optional issue signals are unavailable
- Issue-signal evidence appears only as secondary input in the JSON and summary outputs

## Local Run With Explicit Beads Sync

```bash
./scripts/codex-cli-update-monitor.sh \
  --issue-action upsert \
  --issue-target moltinger-222 \
  --json-out .tmp/current/codex-update-report.json \
  --summary-out .tmp/current/codex-update-summary.md
```

Expected result:

- In the first implementation slice, the request is recorded as `issue_action.mode=skipped` without mutating Beads
- A later User Story 3 slice will turn the same explicit flags into real Beads create/update behavior

## Manual Workflow Run

Trigger the planned GitHub Actions workflow manually with the same inputs used locally. If the runner does not have `codex` installed, provide `local_version` explicitly.

Expected result:

- Workflow uploads JSON and Markdown artifacts with the same core fields as the local run
- Workflow does not self-upgrade Codex
- Workflow leaves tracker state unchanged unless explicit sync inputs are provided

## Validation Checklist

1. Run the local command with default read-only behavior and confirm no tracker mutation occurs.
2. Confirm the JSON report conforms to `contracts/monitor-report.schema.json`.
3. Confirm the summary clearly explains why the recommendation was chosen.
4. Run the manual workflow path and verify artifact parity with the local path.
5. Run the explicit issue-sync path and confirm the issue action is auditable in the report, even before US3 lands real tracker mutation.
