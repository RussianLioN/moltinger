# Codex CLI Update Monitoring Speckit Seed

Date: 2026-03-09
Issue: `molt-2`
Status: research complete, ready for a dedicated feature branch

This file is the foundation for a later Speckit cycle. It is intentionally branch-neutral because the current session is in `uat/006-git-topology-registry`, not in a dedicated feature branch for Codex update monitoring.

## Suggested Branch Short Name

`codex-update-monitor`

## Ready-To-Paste `/speckit.specify` Prompt

Create a script-first workflow for this repository that monitors Codex CLI updates and selected upstream Codex issues, compares them with the locally installed Codex version, enabled features, and repository workflow patterns, and produces both a machine-readable report and a human recommendation summary. The workflow should tell the operator whether to upgrade now, defer, or ignore the change, explain which new Codex capabilities are relevant to this repository, and optionally create or update a Beads follow-up item when action is recommended. The first version must be safe for on-demand local runs and CI/manual automation, must avoid automatic self-upgrade, and should be designed so the collector logic can later be wrapped as a reusable skill.

## Suggested Scope

### In Scope

- detect installed Codex CLI version and selected local config/features
- inspect official Codex changelog entries
- optionally inspect selected upstream issue feeds relevant to Codex CLI workflow risk
- emit deterministic JSON output plus a concise Markdown summary
- apply a recommendation rubric: `upgrade-now`, `upgrade-later`, `ignore`, or `investigate`
- optional explicit-flag issue creation or update in Beads
- reusable wrapping layer suitable for future skill packaging

### Out Of Scope

- automatic installation or self-upgrade of Codex CLI
- background daemon behavior
- silent mutation of repo instructions or launcher scripts
- plugin-only packaging for v1
- treating remote issue activity alone as proof of required action

## Candidate User Stories

### US1: Operator Gets Update Decision Fast

As a repository operator, I want to run one command and see whether the installed Codex CLI is behind, what changed upstream, and whether this repository should act now, so that I do not need to manually browse release notes every time.

### US2: Maintainer Gets Workflow-Relevant Analysis

As a workflow maintainer, I want the report to map upstream changes to this repository's real practices such as worktrees, approvals, skills, AGENTS, and non-interactive runs, so that upgrade recommendations are specific rather than generic.

### US3: Backlog Gets Actionable Follow-Up

As a backlog owner, I want a recommended upgrade to optionally create or refresh a tracked issue with evidence and next steps, so that useful upgrades do not disappear into chat history.

### US4: Reuse Across Repositories Remains Possible

As a future maintainer, I want the collector and report contract to be reusable from a skill or plugin later, so that the first implementation does not trap the workflow inside this one repository.

## Candidate Functional Requirements

1. The workflow MUST detect the locally installed Codex CLI version.
2. The workflow MUST identify key local Codex configuration and enabled features that affect repository workflow.
3. The workflow MUST compare local state against the latest official Codex changelog entries.
4. The workflow MUST produce a deterministic JSON report suitable for machine parsing.
5. The workflow MUST produce a concise human-readable summary that cites the evidence behind its recommendation.
6. The workflow MUST classify the result as `upgrade-now`, `upgrade-later`, `ignore`, or `investigate`.
7. The workflow MUST explain which upstream changes are relevant to this repository and which are not.
8. The default execution path MUST be read-only with respect to repository runtime behavior and tracker state.
9. Issue creation or update MUST require an explicit opt-in flag.
10. The design MUST allow a later thin skill wrapper without rewriting the collector contract.

## Candidate Success Criteria

1. An operator can determine whether action is needed in under 5 minutes without manually reading upstream release docs.
2. The report identifies the local version, latest checked version, and the top workflow-relevant changes for the repository in every successful run.
3. When the recommendation is `upgrade-now` or `investigate`, the report includes evidence strong enough to create a follow-up issue without additional manual source gathering.
4. When no workflow-relevant change exists, the workflow recommends `ignore` or `upgrade-later` instead of generating noisy follow-up work.

## Suggested Technical Direction

### Preferred Shape

```text
collector script -> recommendation/report layer -> optional issue sync -> later skill wrapper
```

### Candidate Artifacts

- `scripts/codex-cli-update-monitor.sh`
- `tests/unit/test_codex_cli_update_monitor.sh`
- `docs/reports/codex-cli-update-report-YYYY-MM-DD.md`
- optional `.claude/skills/codex-update-monitor/SKILL.md`

### Recommended Contract Fields

At minimum, the JSON report should include:

- `checked_at`
- `local_version`
- `latest_version`
- `version_status`
- `local_features`
- `relevant_changes`
- `non_relevant_changes`
- `recommendation`
- `evidence`
- `issue_action`

## Open Questions For Speckit Clarify

1. Should issue monitoring be limited to official Codex release notes in v1, or should v1 already include selected upstream issue feeds?
2. Should the first delivery support only manual local runs, or also a CI/manual workflow entrypoint?
3. Should the follow-up tracker target Beads only, or should the design reserve a second sink such as GitHub Issues or Linear?

## Implementation Lanes To Expect

1. Collector script and JSON contract
2. Recommendation rubric and summary rendering
3. Tracker integration behind explicit opt-in
4. Docs, runbook, and future skill wrapper
5. Tests with fixed fixtures for upstream inputs

## Next Step

When a dedicated branch is created for this topic, start with:

1. `/speckit.specify` using the prompt above
2. `/speckit.plan`
3. `/speckit.tasks`
4. `bd` import or issue linkage once the feature package exists
