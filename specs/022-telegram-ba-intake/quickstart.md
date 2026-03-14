# Quickstart: Factory Business Analyst Intake

## Purpose

This quickstart is for validation and continued implementation handoff of the conversational discovery slice.

It confirms six things:

1. the new feature is clearly separated from the already completed `020` downstream factory slice
2. discovery starts with a factory business interview, not a pre-filled JSON brief
3. the user confirms a requirements brief before downstream artifact generation
4. examples, contradictions, and resume behavior are treated as first-class concerns
5. handoff into the existing concept-pack pipeline remains explicit and traceable
6. reopening a confirmed brief preserves prior confirmation and handoff history instead of overwriting it

## 1. Verify Package Integrity

Run:

```bash
git status --short specs/022-telegram-ba-intake docs/GIT-TOPOLOGY-REGISTRY.md
.specify/scripts/bash/check-prerequisites.sh --json
rg -n "022-telegram-ba-intake|Factory Business Analyst Intake" \
  specs/022-telegram-ba-intake/spec.md \
  specs/022-telegram-ba-intake/plan.md \
  specs/022-telegram-ba-intake/research.md \
  specs/022-telegram-ba-intake/data-model.md \
  specs/022-telegram-ba-intake/contracts \
  specs/022-telegram-ba-intake/quickstart.md
```

Expected result:

- the Speckit package exists for `022-telegram-ba-intake`
- planning artifacts reference the new discovery-first scope
- the package clearly points downstream to `020-agent-factory-prototype` rather than duplicating defense/swarm/deploy concerns

## 2. Validate Guided Discovery Behavior

Use:

- [spec.md](./spec.md)
- [contracts/discovery-session-contract.md](./contracts/discovery-session-contract.md)

Expected feature flow:

1. User starts a new AI-agent project through a supported factory interface.
2. Moltinger explains that it acts as a factory business-analyst guide.
3. The agent asks adaptive follow-up questions until critical topics are sufficiently covered.
4. The session keeps track of unresolved topics instead of pretending the brief is complete.

Validation questions:

- Can the user answer in non-technical language?
- Does the system ask the next useful question instead of using a rigid questionnaire?
- Are missing topics, assumptions, and open questions explicitly separated?

## 3. Validate Brief Draft And Confirmation

Use:

- [contracts/requirements-brief-contract.md](./contracts/requirements-brief-contract.md)

Expected feature flow:

1. Discovery produces a reviewable draft brief.
2. The user can request corrections in normal conversational language.
3. The agent regenerates the draft brief without losing structure.
4. The brief becomes eligible for downstream handoff only after explicit confirmation.

Validation questions:

- Does the brief include user story, examples, constraints, and success metrics?
- Can the user correct the brief without editing files directly?
- Is confirmation clearly separate from later concept approval?

## 4. Validate Example And Clarification Handling

Use:

- [contracts/clarification-loop-contract.md](./contracts/clarification-loop-contract.md)

Expected feature flow:

1. User provides examples of inputs, outputs, rules, or exceptions.
2. The agent maps them into structured requirement context.
3. Contradictory or unsafe examples produce explicit clarification items.
4. Unresolved issues are either answered or carried as open risks before confirmation.

Validation questions:

- Are examples preserved as structured cases instead of disappearing into free text?
- Does the system identify contradictions before confirmation?
- Does the system request sanitized substitutes for sensitive data examples?

## 5. Validate Handoff Into The Existing Factory Pipeline

Use:

- [contracts/factory-handoff-contract.md](./contracts/factory-handoff-contract.md)
- [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)

Expected feature flow:

1. A confirmed brief becomes one canonical handoff record.
2. Downstream concept-pack generation is blocked until that handoff is ready.
3. Provenance remains traceable from discovery session to confirmed brief to concept artifacts.

Validation questions:

- Can a downstream operator tell which brief version fed the concept pack?
- Is concept-pack generation blocked for unconfirmed or superseded briefs?
- Does the new slice strengthen the existing factory instead of branching away from it?

Reference validation chain:

```bash
python3 scripts/agent-factory-discovery.py run \
  --source tests/fixtures/agent-factory/discovery/brief-confirmed-handoff.json \
  --output /tmp/discovery-handoff-out.json

python3 scripts/agent-factory-intake.py \
  --source /tmp/discovery-handoff-out.json \
  --output /tmp/discovery-handoff-intake.json

python3 scripts/agent-factory-artifacts.py generate \
  --input /tmp/discovery-handoff-intake.json \
  --output-dir /tmp/discovery-handoff-pack \
  --output /tmp/discovery-handoff-pack.json
```

Expected result:

- discovery returns or preserves one ready `factory_handoff_record`
- intake returns `ready_for_pack` from the discovery-shaped payload
- generated concept-pack manifest includes `source_provenance` and per-artifact `generated_from`

## 6. Validate Resume And Reopen Behavior

Expected feature flow:

1. An interrupted session can be resumed from an existing discovery snapshot.
2. The runtime returns `resume_context` with the restored state and pending question.
3. A confirmed brief can be reopened into a new version.
4. Previous confirmation and handoff records move into history instead of being discarded.

Validation questions:

- Does resume preserve the exact pending question or blocking clarification?
- Does reopening create a new brief version rather than mutate the old confirmed one?
- Are `confirmation_history` and `handoff_history` present after reopen?

## 7. Current Readiness Check

Confirm:

- [x] the feature has a complete spec package
- [x] discovery and downstream factory boundaries are explicit
- [x] confirmation is defined as a separate gate before concept-pack generation
- [x] example-driven clarification and resume behavior are modeled as first-class concerns
- [x] handoff into the existing `020` flow is part of the contract

## 8. Handoff Rule

This feature is ready for continued implementation only when:

1. `tasks.md` exists and reflects the discovery-first execution order
2. runtime work updates both this package and the downstream `020` package when the handoff contract changes
3. topology documentation is refreshed after branch or worktree mutations
4. the eventual implementation adds matching fixtures and tests for interview, confirmation, handoff, and resume behavior

## 9. Clarification Guard

For this package, interpret the legacy id `022-telegram-ba-intake` as:

- factory business-analyst intake on `Moltis`
- `Telegram` as the current reference/default interface
- future `Moltinger UI`, `Moltis UI`, or other factory UI adapters as equivalent interaction surfaces for the same discovery logic
