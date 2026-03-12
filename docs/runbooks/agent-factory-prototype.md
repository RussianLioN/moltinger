# Agent Factory Prototype Runbook

## Purpose

This runbook describes the MVP0 intake-to-playground path for `020-agent-factory-prototype`.

Current scope:

1. normalize one Telegram-style intake request
2. create one canonical concept record
3. generate a synchronized concept pack
4. record one defense outcome with structured feedback
5. regenerate the concept pack without losing previous reviewed state
6. run one approved concept through the prototype swarm
7. package one runnable playground bundle
8. expose working, downloadable, and operator-reviewable evidence files

## Inputs

The intake stage expects one JSON payload with:

- `raw_problem_statement`
- `captured_answers.target_business_problem`
- `captured_answers.target_users`
- `captured_answers.current_workflow_summary`
- `captured_answers.constraints_or_exclusions`
- `captured_answers.measurable_success_expectation`

Recommended seed fixture:

- `tests/fixtures/agent-factory/concept-intake.json`

## Commands

### 1. Normalize intake into a concept record

```bash
python3 scripts/agent-factory-intake.py \
  --source tests/fixtures/agent-factory/concept-intake.json \
  --output /tmp/agent-factory-intake.json
```

Expected result:

- `status = ready_for_pack` for a complete request
- `status = clarifying` plus `follow_up_questions` when critical fields are missing
- one canonical `concept_record`
- one `artifact_context` for concept-pack generation

### 2. Generate the concept pack

```bash
python3 scripts/agent-factory-artifacts.py generate \
  --input /tmp/agent-factory-intake.json \
  --output-dir /tmp/agent-factory-pack \
  --output /tmp/agent-factory-pack-report.json
```

Expected output tree:

```text
/tmp/agent-factory-pack/
├── concept-pack.json
├── concept-record.json
├── working/
│   ├── project-doc.md
│   ├── agent-spec.md
│   └── presentation.md
└── downloads/
    ├── project-doc.md
    ├── agent-spec.md
    └── presentation.md
```

Notes:

- `working/` is the editable source-first set
- `downloads/` is the user-facing set to send through Telegram
- `concept-pack.json` is the canonical manifest for alignment and delivery

### 3. Verify artifact alignment

```bash
python3 scripts/agent-factory-artifacts.py check-alignment \
  --manifest /tmp/agent-factory-pack/concept-pack.json
```

Expected result:

- exit `0` and `status = aligned` for a fresh pack
- exit `1` and `status = drift_detected` if any artifact diverges

### 4. Record defense outcome

```bash
python3 scripts/agent-factory-review.py \
  --manifest /tmp/agent-factory-pack/concept-pack.json \
  --feedback tests/fixtures/agent-factory/defense-feedback.json \
  --output /tmp/agent-factory-review.json
```

Expected result:

- `status = review_recorded`
- `outcome` stored in `defense_review`
- `next_action` becomes one of:
  - `ready_for_production`
  - `regenerate_artifacts`
  - `concept_rejected`
  - `wait_for_decision`
- `production_approval` exists only for `approved`

### 5. Regenerate after review or rework

```bash
python3 scripts/agent-factory-artifacts.py generate \
  --input /tmp/agent-factory-review.json \
  --output-dir /tmp/agent-factory-pack \
  --output /tmp/agent-factory-pack-after-review.json
```

Expected result:

- same-version review updates auto-bump `artifact_revision`
- `rework_requested` bumps `concept_version` and resets artifact revision to `r1`
- previous current pack is archived under `history/`
- manifest exposes `approval_gate.status = unlocked|blocked`

### 6. Run swarm for one approved concept

For the happy-path prototype, use an approved review payload and regenerate the pack before running the swarm:

```bash
cat >/tmp/agent-factory-approved-review.json <<'JSON'
{
  "defense_review": {
    "review_id": "defense-review-approved-demo",
    "concept_id": "concept-invoice-approval-factory-demo",
    "concept_version": "0.1.0",
    "outcome": "approved",
    "reviewers": ["factory_board"],
    "feedback_summary": "Концепция одобрена для запуска swarm.",
    "decision_notes": "Разрешить запуск prototype swarm.",
    "reviewed_at": "2026-03-12T21:00:00Z"
  },
  "feedback_items": [],
  "expected_next_step_summary": "Запустить production swarm для approved concept version."
}
JSON

python3 scripts/agent-factory-review.py \
  --manifest /tmp/agent-factory-pack/concept-pack.json \
  --feedback /tmp/agent-factory-approved-review.json \
  --output /tmp/agent-factory-approved-review-result.json

python3 scripts/agent-factory-artifacts.py generate \
  --input /tmp/agent-factory-approved-review-result.json \
  --output-dir /tmp/agent-factory-pack \
  --output /tmp/agent-factory-approved-pack.json

python3 scripts/agent-factory-swarm.py run \
  --manifest /tmp/agent-factory-pack/concept-pack.json \
  --output-dir /tmp/agent-factory-swarm \
  --output /tmp/agent-factory-swarm-output.json
```

Expected result:

- `status = completed`
- `swarm_run.run_status = completed`
- five ordered stages are present:
  - `coding`
  - `testing`
  - `validation`
  - `audit`
  - `assembly`
- every stage publishes at least one `evidence_ref`
- the result includes `playground_package` and `evidence_bundle`

### 7. Inspect the playground output

Expected output tree:

```text
/tmp/agent-factory-swarm/
├── artifacts/
│   ├── coding/output-summary.md
│   ├── testing/report.json
│   ├── validation/checklist.md
│   ├── audit/alignment-report.md
│   └── evidence/
│       ├── bundle-manifest.json
│       └── bundle.zip
├── assembly/
│   ├── playground-bundle/
│   │   ├── Dockerfile
│   │   ├── playground_server.py
│   │   ├── playground-card.json
│   │   ├── synthetic-dataset.json
│   │   ├── launch-instructions.md
│   │   ├── README.md
│   │   └── playground-package.json
│   └── <concept>-bundle.tar.gz
├── swarm-playground-source.json
└── swarm-run.json
```

Key operator files:

- `swarm-run.json` is the canonical swarm manifest
- `artifacts/evidence/bundle.zip` is the reviewable evidence bundle
- `assembly/playground-bundle/playground-package.json` is the canonical playground manifest
- `assembly/<concept>-bundle.tar.gz` is the downloadable demo bundle

## Delivery Semantics

For MVP0 the user-facing downloads are the files under `downloads/`.

Operational rule:

- never require the user to browse server paths manually
- always treat `concept-pack.json` as the source of truth for which files are publishable
- use the `download_ref` values from the manifest when wiring Telegram `sendDocument` later

## Current Artifact Contract

Each concept pack must contain:

- `project_doc`
- `agent_spec`
- `presentation`

Each artifact must carry:

- `concept_id`
- `concept_version`
- `artifact_revision`
- one shared alignment marker with the same `sync_hash`

Concept pack manifest must also carry:

- `artifact_context`
- `review_history`
- `feedback_history`
- `approval_gate`
- `history`

## Current Validation

Implemented tests:

- `tests/component/test_agent_factory_artifacts.sh`
- `tests/component/test_agent_factory_playground.sh`
- `tests/integration_local/test_agent_factory_intake.sh`
- `tests/integration_local/test_agent_factory_review.sh`
- `tests/integration_local/test_agent_factory_swarm.sh`

Typical local validation:

```bash
./tests/run.sh --lane static --filter static_fleet_registry --json
./tests/run.sh --lane component --filter component_agent_factory_artifacts --json
./tests/run.sh --lane component --filter component_agent_factory_playground --json
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_intake --json
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_review --json
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_swarm --json
```

## Known Boundaries

- The concept pack is Markdown-first in this MVP0 slice.
- Downloadable outputs currently use Markdown copies; export to additional formats is a later enhancement.
- Telegram publishing is represented by manifest-ready download refs, not by live bot file sending in this slice.
- The prototype swarm is contract-driven and evidence-first; it does not yet spawn live long-running worker runtimes.
- The prototype ends at a runnable playground bundle plus evidence. Production deployment remains MVP1.
