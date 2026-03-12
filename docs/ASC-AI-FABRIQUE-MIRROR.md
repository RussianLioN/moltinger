# ASC AI Fabrique Mirror

**Purpose**: Keep the current repository self-sufficient for agent-factory planning by mirroring the upstream ASC concept and roadmap docs inside this project.
**Upstream Repository**: `https://github.com/RussianLioN/ASC-AI-agent-fabrique`
**Verified Upstream Commit**: `54f359495b8926887dc8c632b74f95fee523b959`
**Mirror Refreshed**: `2026-03-12`
**Mirror Scope**: top-level `*.md` and `*.bpmn` files from upstream `docs/asc-roadmap/` and `docs/concept/`

## What Is Mirrored

### Core ASC roadmap

- `docs/asc-roadmap/INDEX.md`
- `docs/asc-roadmap/strategic_roadmap.md`
- `docs/asc-roadmap/GLOSSARY.md`
- `docs/asc-roadmap/meta_block_registry.md`
- `docs/asc-roadmap/defense_poc_template.md`
- `docs/asc-roadmap/self_referential_mapping.md`
- `docs/asc-roadmap/ai_tools_strategy.md`
- `docs/asc-roadmap/devops_infrastructure_tz.md`

### Concept and management materials

- `docs/concept/INDEX.md`
- `docs/concept/ASC AI Fabrique - Концепция автономной фабрики цифровых сотрудников.md`
- `docs/concept/ASC AI Fabrique 2.0 - Концепция фабрики развития.md`
- `docs/concept/ASC AI Fabrique 2.0 - План двухстраничной инфографической презентации для руководства.md`
- `docs/concept/ASC AI Fabrique 2.0 - Таблица изменений концепции.md`
- `docs/concept/ASC AI Fabrique 2.0 - Этапы развития фабрики и критический разбор.md`
- additional top-level concept markdown and BPMN files required for context continuity

## What Is Intentionally Not Mirrored

- PDF, HTML, PPTX, PNG, SVG, ZIP, and other bulky binary/export artifacts
- nested presentation-export folders from upstream `docs/concept/`

Those assets remain available in the upstream repository when a later session needs exact presentation renders rather than planning context.

## How To Use This Mirror

### Start here for concept context

1. `docs/asc-roadmap/INDEX.md`
2. `docs/concept/INDEX.md`
3. `docs/plans/parallel-doodling-coral.md`
4. `docs/plans/agent-factory-lifecycle.md`

### Use these local project artifacts for implementation context

- `config/moltis.toml`
- `config/fleet/agents-registry.json`
- `config/fleet/policy.json`
- `docs/telegram-e2e-on-demand.md`
- `docs/runbooks/`

### Use this Speckit package for the active prototype definition

- `specs/020-agent-factory-prototype/spec.md`
- `specs/020-agent-factory-prototype/research.md`
- `specs/020-agent-factory-prototype/plan.md`
- `specs/020-agent-factory-prototype/tasks.md`
- `specs/020-agent-factory-prototype/quickstart.md`

## Session Recovery Path

When a new session needs to restore context without any workstation-local hints, read in this order:

1. `docs/ASC-AI-FABRIQUE-MIRROR.md`
2. `docs/asc-roadmap/INDEX.md`
3. `docs/concept/INDEX.md`
4. `docs/plans/parallel-doodling-coral.md`
5. `docs/plans/agent-factory-lifecycle.md`
6. `specs/020-agent-factory-prototype/spec.md`
7. `specs/020-agent-factory-prototype/tasks.md`
8. `specs/020-agent-factory-prototype/quickstart.md`
9. `docs/runbooks/agent-factory-prototype.md`
10. `config/fleet/agents-registry.json`
11. `config/fleet/policy.json`

This path is intentionally repo-local only. No workstation-local absolute path should be required to find concept context, active implementation scope, or platform contracts.

## Reading Paths

### For business framing and defense

1. `docs/concept/ASC AI Fabrique 2.0 - Концепция фабрики развития.md`
2. `docs/concept/ASC AI Fabrique 2.0 - План двухстраничной инфографической презентации для руководства.md`
3. `docs/asc-roadmap/defense_poc_template.md`

### For platform architecture and swarm logic

1. `docs/asc-roadmap/meta_block_registry.md`
2. `docs/asc-roadmap/self_referential_mapping.md`
3. `docs/plans/agent-factory-lifecycle.md`
4. `config/fleet/agents-registry.json`
5. `config/fleet/policy.json`

### For MVP0 planning in this repository

1. `docs/plans/parallel-doodling-coral.md`
2. `docs/ASC-AI-FABRIQUE-MIRROR.md`
3. `specs/020-agent-factory-prototype/spec.md`
4. `specs/020-agent-factory-prototype/tasks.md`
5. `specs/020-agent-factory-prototype/quickstart.md`

## Integrity Checks

Use these local checks before landing changes that affect mirror navigation or planning continuity:

```bash
./tests/run.sh --lane component --filter component_agent_factory_context_mirror --json
ASC_LEGACY_SEGMENT_1="coding/ASC-AI-agent"
ASC_LEGACY_SEGMENT_2="-fabrique"
rg -n "${ASC_LEGACY_SEGMENT_1}${ASC_LEGACY_SEGMENT_2}" \
  docs/ASC-AI-FABRIQUE-MIRROR.md \
  docs/plans/parallel-doodling-coral.md \
  docs/research/openclaw-moltis-research.md \
  specs/020-agent-factory-prototype/spec.md \
  specs/020-agent-factory-prototype/plan.md \
  specs/020-agent-factory-prototype/research.md \
  specs/020-agent-factory-prototype/data-model.md \
  specs/020-agent-factory-prototype/tasks.md \
  specs/020-agent-factory-prototype/contracts
```

Expected result:

- component mirror-integrity test passes
- no active planning artifact depends on the workstation-local upstream clone

## Maintenance Rule

When refreshing this mirror:

1. verify the upstream commit or `HEAD`
2. update this provenance file
3. keep local project docs pointing to in-repo mirror paths instead of workstation-specific absolute paths
4. reconcile the active Speckit package if the upstream concept materially changes prototype scope
