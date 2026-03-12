# Agent Factory Prototype Runbook

## Purpose

This runbook describes the MVP0 intake-to-concept-pack path for `020-agent-factory-prototype`.

Current scope:

1. normalize one Telegram-style intake request
2. create one canonical concept record
3. generate a synchronized concept pack
4. expose working and downloadable artifact files

Defense loop and swarm production are documented in the spec but are not part of this runbook section yet.

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

## Current Validation

Implemented tests:

- `tests/component/test_agent_factory_artifacts.sh`
- `tests/integration_local/test_agent_factory_intake.sh`

Typical local validation:

```bash
./tests/run.sh --lane component --filter component_agent_factory_artifacts --json
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_intake --json
```

## Known Boundaries

- The concept pack is Markdown-first in this MVP0 slice.
- Downloadable outputs currently use Markdown copies; export to additional formats is a later enhancement.
- Telegram publishing is represented by manifest-ready download refs, not by live bot file sending in this slice.
