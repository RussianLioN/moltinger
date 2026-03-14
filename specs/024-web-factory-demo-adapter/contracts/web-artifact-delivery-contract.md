# Contract: Web Artifact Delivery

## Purpose

Define how a confirmed browser brief triggers downstream factory generation and returns the resulting concept-pack artifacts as browser downloads.

## Required Prerequisites

- active `WebDemoSession`
- current brief version in confirmed state
- ready `FactoryHandoffRecord`

## Required Outputs

- downstream intake invocation
- downstream concept-pack generation invocation
- one or more `BriefDownloadArtifact` records
- safe status and provenance links back to the confirmed brief

## Rules

- Downloads are published only after downstream generation reaches a ready state.
- The browser UI must not require manual operator copy-paste of artifact paths.
- User-facing delivery state must remain safe for non-technical users.
- `project doc`, `agent spec`, and `presentation` are the minimum visible artifacts for success.

## Failure Conditions

- downloads are exposed before the active brief is confirmed
- downstream generation requires manual reconstruction from chat text
- artifact delivery exposes internal filesystem paths
- artifact provenance back to the confirmed brief is lost
