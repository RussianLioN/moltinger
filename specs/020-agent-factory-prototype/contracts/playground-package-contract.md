# Contract: Playground Package

## Purpose

Define the final MVP0 output that the user can review and demonstrate after autonomous production succeeds.

## Required Contents

- runnable container reference or package
- launch instructions
- synthetic or test-data profile
- evidence bundle reference
- concept version reference

## Rules

- Playground must be demonstrable without production deployment.
- Playground data must not contain live business data in this prototype.
- The package must remain traceable to the exact concept version and swarm run that produced it.
- The user must be able to access the package without direct shell access to the server.

## Required Review Questions

- Does the playground demonstrate the approved use case?
- Is the behavior consistent with the approved specification?
- Is the evidence bundle sufficient to understand test, validation, and audit outcomes?
- Is post-playground feedback captured for rework or MVP1 handoff?

## Failure Conditions

- package exists but cannot be launched
- package is detached from its concept or evidence lineage
- package requires live data or deployment-only infrastructure to be demonstrated
