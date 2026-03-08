# Specify Template Instructions

This directory contains Speckit constitution and template sources that shape future spec generation.

## Rules

1. Treat changes here as high-leverage. They affect future specs across the repository.
2. Keep template placeholders, headings, and section markers stable unless you are intentionally migrating the contract.
3. Update constitution and templates together when policy changes would otherwise create drift.
4. Do not confuse `.specify/` source templates with active `specs/` work packages. Runtime work still reconciles `specs/<feature>/`.
5. Prefer small, explicit template changes with a clear rationale in the diff or handoff.

## Validation

After changes here, verify:
- referenced template files still exist
- the constitution still matches repository policy
- template changes remain compatible with current `specs/` expectations

## Escalation

Stop and ask before:
- deleting templates
- broadly rewriting constitution semantics
- changing placeholder structure in a way that would break downstream generation
