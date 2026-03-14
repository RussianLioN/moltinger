# Codex CLI Update Monitor

`scripts/codex-cli-update-monitor.sh` compares the local Codex CLI state with recent upstream Codex releases, maps upstream changes to this repository's workflow traits, and emits both a JSON report and a Markdown summary.

## Prerequisites

- `bash`
- `jq`
- `python3` with `tomllib` support
- `curl` when using URL-backed release or issue sources

The script reads local Codex config from `~/.codex/config.toml` by default. Override this with `--config-file` or `CODEX_UPDATE_MONITOR_CONFIG_FILE` when testing fixtures.

## Local Usage

Typical local run:

```bash
./scripts/codex-cli-update-monitor.sh \
  --json-out .tmp/current/codex-update-report.json \
  --summary-out .tmp/current/codex-update-summary.md
```

Useful options:

- `--stdout summary|json|none`
- `--local-version 0.112.0`
- `--release-file tests/fixtures/codex-update-monitor/releases.json`
- `--release-url https://developers.openai.com/codex/changelog`
- `--include-issue-signals`
- `--issue-signals-file tests/fixtures/codex-update-monitor/issue-signals.json`
- `--issue-signals-url https://api.github.com/repos/openai/codex/issues?state=open&per_page=20`
- `--issue-action upsert`
- `--issue-target moltinger-222`
- `--issue-threshold upgrade-now`
- `--beads-db /absolute/path/to/the-intended-worktree/.beads/beads.db`

If no issue flags are passed and the recommendation crosses the issue threshold, the report records `issue_action.mode=suggested` and explains how to rerun with explicit sync.

If you pass `--issue-action upsert`, the script will:

- create a new Beads follow-up when no `--issue-target` is supplied
- update the target issue when `--issue-target <id>` is supplied
- skip mutation and say why when the recommendation is below threshold or Beads prerequisites are missing

This tracker sync path is intended for local runs. In a dedicated worktree, the script now reuses the Beads ownership resolver and can auto-target the current worktree-local DB for explicit upserts. In the canonical root, implicit tracker mutation is blocked; use `--beads-db` only when a root-scoped admin/troubleshooting write is truly intended.

## Output Contract

Every successful run emits a JSON object with:

- `checked_at`
- `local_version`
- `latest_version`
- `version_status`
- `local_features`
- `repo_workflow_traits`
- `sources`
- `relevant_changes`
- `non_relevant_changes`
- `recommendation`
- `evidence`
- `issue_action`

Recommendation values:

- `upgrade-now`
- `upgrade-later`
- `ignore`
- `investigate`

`--stdout json` is the wrapper-safe mode. It prints only the machine-readable contract to stdout. `--stdout none` suppresses stdout and relies on `--json-out` / `--summary-out`.

`issue_action.mode` now has these practical meanings:

- `none`: no follow-up is needed and sync was not requested
- `suggested`: follow-up is recommended, but the run stayed read-only
- `created`: explicit sync created a new Beads issue
- `updated`: explicit sync updated an existing Beads issue
- `skipped`: sync was requested but not executed, with an explicit reason in `issue_action.notes`

## Relevance Rules

The monitor currently treats these repo traits as high-signal:

- worktree discipline
- approval and sandbox boundaries
- multi-agent usage
- `js_repl` usage
- non-interactive Codex execution
- AGENTS-bound workflow surfaces

Plugin-related changes are currently classified as low relevance unless they also intersect with skills or MCP usage. Optional issue signals are advisory only and do not force an upgrade recommendation on their own.

## Manual Workflow

Use `.github/workflows/codex-cli-update-monitor.yml` for a CI-safe manual run.

Recommended inputs:

- `local_version`: set this when the GitHub runner does not have `codex` installed
- `release_url`: defaults to the official Codex changelog
- `include_issue_signals`: opt-in advisory issue scan
- `issue_signals_url`: defaults to `openai/codex` GitHub issues

The workflow uploads:

- `codex-update-report.json`
- `codex-update-summary.md`

The workflow does not currently expose Beads mutation inputs because GitHub runners do not share this workstation's Beads DB path. Use local runs for explicit `upsert` behavior.

## Validation

Local validation for this first slice:

```bash
bash -n scripts/codex-cli-update-monitor.sh
./tests/component/test_codex_cli_update_monitor.sh
```
