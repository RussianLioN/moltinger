# Data Model: Full Moltis-Native Codex Update Skill

## UpstreamReleaseSnapshot

Represents one normalized read of official Codex CLI upstream sources.

Fields:

- `source_id`
- `fetched_at`
- `latest_version`
- `primary_status`
- `highlights_ru[]`
- `issue_signal_summary`
- `fingerprint`

## CodexUpdateSkillState

Moltis-owned persistent state for this capability.

Fields:

- `last_seen_fingerprint`
- `last_seen_version`
- `last_alert_fingerprint`
- `last_alert_at`
- `last_run_at`
- `last_run_mode` (`manual|scheduler`)
- `last_result`
- `degraded_reason`

## ProjectProfile

Optional static description of how a project maps Codex changes to practical follow-up.

Fields:

- `profile_id`
- `project_name`
- `owner`
- `traits[]`
- `relevance_rules[]`
- `relevance_rules[].title_ru`
- `relevance_rules[].next_steps_ru[]`
- `relevance_rules[].priority_paths[]`
- `relevance_rules[].recommendation_template_id`
- `recommendation_templates[]`
- `recommendation_templates[].title_ru`
- `recommendation_templates[].rationale_ru`
- `recommendation_templates[].next_steps_ru[]`
- `recommendation_templates[].impacted_paths[]`
- `fallback_recommendation`

## CodexUpdateDecision

One Moltis-native verdict produced from the snapshot plus optional profile.

Fields:

- `decision` (`ignore|upgrade-later|upgrade-now|investigate`)
- `severity`
- `why_it_matters_ru`
- `summary_ru`
- `project_specific`
- `recommendation_count`

## RecommendationBundle

Human-facing next steps returned on demand or after acceptance.

Fields:

- `headline_ru`
- `summary_ru`
- `items[]`
- `impacted_paths[]`
- `profile_source`
- `items[].source_rule_id`
- `items[].source_template_id`

## CodexUpdateAuditRecord

Machine-readable record for one skill run.

Fields:

- `run_id`
- `run_mode`
- `snapshot_fingerprint`
- `decision`
- `delivery_status`
- `profile_status`
- `started_at`
- `completed_at`
- `error`
