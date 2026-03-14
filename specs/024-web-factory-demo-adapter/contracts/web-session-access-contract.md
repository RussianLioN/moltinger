# Contract: Web Session Access

## Purpose

Define how the web-first demo surface grants controlled access and maps one browser session to the correct active factory project.

## Required Inputs

- browser request to the demo subdomain
- access grant or equivalent controlled-entry proof
- optional existing browser session token

## Required Behavior

- validate access before opening an active project workspace
- create or restore one `WebDemoSession`
- bind one active `BrowserProjectPointer` to the session
- expose a safe `WebDemoStatusSnapshot` for the current project state

## Rules

- Access failure must fail closed and show a controlled prompt, not internal diagnostics.
- One browser session must not silently mutate a different user's active project.
- Refresh or revisit must restore the correct active project when a valid session exists.
- Session routing must remain compatible with later follow-up adapters such as `023`.

## Failure Conditions

- browser access reaches an active project without passing the demo gate
- session resume restores the wrong project
- unauthorized access exposes brief, artifact, or internal path data
- refresh destroys the active project pointer
