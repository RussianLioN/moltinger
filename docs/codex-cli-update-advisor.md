# Codex CLI Update Advisor

`scripts/codex-cli-update-advisor.sh` wraps the completed update monitor and answers the operational question the monitor leaves open: is this result new, what in this repository should we likely change, and should we create or update a tracked follow-up?

## What The User Sees

The advisor is intentionally simple:

1. It reads the current monitor result or runs the monitor itself.
2. It decides whether this state is new, already seen, silent, or investigatory.
3. It proposes concrete repository follow-up items with impacted paths.
4. If explicitly requested, it creates or updates a Beads implementation brief.

V1 notification surfaces are low-noise by design:
- terminal summary
- JSON or Markdown artifacts
- optional Beads handoff

External push channels such as desktop notifications, Slack, or Telegram are out of scope for this layer.

## Typical Local Run

```bash
./scripts/codex-cli-update-advisor.sh \
  --release-file tests/fixtures/codex-update-monitor/releases.json \
  --config-file tests/fixtures/codex-update-monitor/config.toml \
  --local-version 0.110.0 \
  --state-file .tmp/current/codex-cli-update-advisor-state.json \
  --json-out .tmp/current/codex-update-advisor-report.json \
  --summary-out .tmp/current/codex-update-advisor-summary.md
```

On a first actionable run, the summary will say roughly:

- notification: `notify`
- recommendation: `upgrade-now` or `upgrade-later`
- top follow-up ideas for this repository

If you rerun with the same actionable state, the advisor should switch to `suppressed` instead of repeating the same alert.

## Reuse An Existing Monitor Report

```bash
./scripts/codex-cli-update-advisor.sh \
  --monitor-report .tmp/current/codex-update-report.json \
  --state-file .tmp/current/codex-cli-update-advisor-state.json \
  --stdout summary
```

This is the wrapper-friendly path. It lets a thin scheduler or future skill keep the monitor and advisor as separate steps while preserving one stable advisor contract.

## Output Contract

Each successful run emits:

- `monitor_snapshot`
- `notification`
- `project_change_suggestions`
- `implementation_brief`
- `issue_action`

Notification values are:

- `notify`: fresh actionable state
- `suppressed`: same actionable state was already seen
- `none`: below notification threshold
- `investigate`: the underlying evidence needs investigation before the repo should change

## How Suggestions Work

The advisor does not invent generic TODOs.

It maps monitor evidence to repository surfaces that are already known to matter here, such as:

- `AGENTS.md`
- `docs/CODEX-OPERATING-MODEL.md`
- `docs/GIT-TOPOLOGY-REGISTRY.md`
- `scripts/codex-profile-launch.sh`
- `.claude/skills/`

Examples of concrete suggestions:

- worktree changes -> review worktree guidance and topology helpers
- approval or sandbox changes -> audit approval guidance and launcher defaults
- `js_repl` changes -> refresh js_repl guidance
- multi-agent or resume changes -> review delegation and resume workflow docs

## Explicit Beads Handoff

Default runs are read-only.

If you want a tracked follow-up, opt in explicitly:

```bash
./scripts/codex-cli-update-advisor.sh \
  --monitor-report .tmp/current/codex-update-report.json \
  --state-file .tmp/current/codex-cli-update-advisor-state.json \
  --issue-action upsert \
  --beads-db /Users/rl/coding/moltinger/.beads/beads.db
```

Behavior:

- no `--issue-target` -> create a new Beads task
- `--issue-target <id>` -> update an existing Beads task
- if the result is suppressed or below threshold -> `issue_action.mode=skipped`

## Make Target

```bash
make codex-update-advisor
```

This writes advisor artifacts into `.tmp/current/` and prints the plain-language summary.

## Validation

Local validation for this feature:

```bash
bash -n scripts/codex-cli-update-advisor.sh
./tests/component/test_codex_cli_update_advisor.sh
./tests/run.sh --lane component --filter codex_cli_update_advisor
make codex-update-advisor
```
