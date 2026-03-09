# Data Model: Codex CLI Update Monitor

## Entities

### LocalCodexState

Represents the local Codex installation and workflow-relevant settings at run time.

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Installed Codex CLI version observed locally |
| `features` | string[] | Enabled or detected local Codex features relevant to workflow behavior |
| `config_traits` | string[] | Important local config toggles normalized into stable labels |
| `detection_status` | enum | `complete`, `partial`, or `missing` |
| `notes` | string[] | Detection caveats or missing-signal explanations |

### UpstreamReleaseSnapshot

Represents the official release information used during the run.

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Latest verified upstream release version considered for the recommendation |
| `published_at` | string | Release publication date |
| `source` | string | Canonical release source identifier |
| `highlights` | string[] | Notable changes extracted from the release |
| `fetch_status` | enum | `ok`, `partial`, or `failed` |

### UpstreamIssueSignal

Represents optional issue-feed evidence that may influence urgency.

| Field | Type | Description |
|-------|------|-------------|
| `source` | string | Issue source identifier |
| `title` | string | Short issue title or normalized summary |
| `status` | string | Open, closed, or equivalent upstream state |
| `relevance_hint` | enum | `high`, `medium`, `low`, or `unknown` |
| `notes` | string[] | Evidence explaining why the signal matters or does not matter |

### RepoWorkflowProfile

Represents normalized repository traits used to assess relevance.

| Field | Type | Description |
|-------|------|-------------|
| `worktree_discipline` | boolean | Whether the repository relies on explicit worktree flows |
| `approval_boundaries` | boolean | Whether repository instructions enforce strong approval/sandbox boundaries |
| `skills_surface` | boolean | Whether the repository actively depends on skills or bridged commands |
| `agents_surface` | boolean | Whether the repository uses multi-agent delegation as a first-class pattern |
| `noninteractive_surface` | boolean | Whether repo workflows rely on non-interactive Codex execution patterns |
| `notes` | string[] | Additional normalized traits used by the recommendation rubric |

### RelevanceAssessment

Represents a single upstream change mapped to repository impact.

| Field | Type | Description |
|-------|------|-------------|
| `change_id` | string | Stable identifier for the assessed upstream change |
| `summary` | string | Human-readable change summary |
| `relevance` | enum | `high`, `medium`, `low`, or `none` |
| `reason` | string | Why the change matters or does not matter to this repository |
| `evidence` | string[] | Supporting facts linking the change to local workflow traits |

### RecommendationDecision

Represents the final run recommendation.

| Field | Type | Description |
|-------|------|-------------|
| `recommendation` | enum | `upgrade-now`, `upgrade-later`, `ignore`, or `investigate` |
| `version_status` | enum | `ahead`, `current`, `behind`, or `unknown` |
| `confidence` | enum | `high`, `medium`, or `low` |
| `reasons` | string[] | Top-level rationale for the decision |
| `next_steps` | string[] | Suggested operator actions |

### IssueAction

Represents the requested or suggested tracker mutation.

| Field | Type | Description |
|-------|------|-------------|
| `mode` | enum | `none`, `suggested`, `created`, `updated`, or `skipped` |
| `target` | string | Beads issue identifier or intended target if known |
| `requested` | boolean | Whether the operator explicitly asked for tracker sync |
| `notes` | string[] | Audit trail for why the issue action happened or was skipped |

### MonitorRunReport

Top-level report entity produced for every run.

| Field | Type | Description |
|-------|------|-------------|
| `checked_at` | string | Run timestamp |
| `local_state` | LocalCodexState | Local installation state |
| `latest_release` | UpstreamReleaseSnapshot | Primary upstream comparison target |
| `issue_signals` | UpstreamIssueSignal[] | Optional secondary evidence |
| `repo_profile` | RepoWorkflowProfile | Repository workflow traits |
| `relevant_changes` | RelevanceAssessment[] | Changes that materially affect the repository |
| `non_relevant_changes` | RelevanceAssessment[] | Changes assessed as low or no impact |
| `decision` | RecommendationDecision | Final recommendation payload |
| `issue_action` | IssueAction | Resulting or suggested tracker action |

## Relationships

- `MonitorRunReport` owns one `LocalCodexState`, one `UpstreamReleaseSnapshot`, one `RepoWorkflowProfile`, one `RecommendationDecision`, and one `IssueAction`.
- `MonitorRunReport` may include zero or more `UpstreamIssueSignal` records.
- `RelevanceAssessment` records are derived by comparing `UpstreamReleaseSnapshot` and `UpstreamIssueSignal` inputs against the `RepoWorkflowProfile`.
- `IssueAction` depends on `RecommendationDecision` and the operator's explicit tracker-sync intent.

## State Notes

- `detection_status=partial` is acceptable for a successful run if the decision records the missing evidence.
- `recommendation=investigate` is the safe fallback when primary evidence is incomplete or contradictory.
- `issue_action.mode=none` is the expected default for standard runs without tracker flags.
