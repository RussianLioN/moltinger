# Hermes cron `origin` delivery contract review

Purpose: identify official doc / tool wording that creates the false expectation that cron output will come back into the live chat as a normal continuation of the conversation, then propose exact wording and UX fixes.

Sources used
- Official docs from `NousResearch/hermes-agent`:
  - `website/docs/user-guide/features/cron.md`
  - `website/docs/guides/cron-troubleshooting.md`
  - `website/docs/developer-guide/cron-internals.md`
- Official source / UX strings from `NousResearch/hermes-agent`:
  - `tools/cronjob_tools.py`
  - `cron/jobs.py`
  - `hermes_cli/cron.py`
  - `cron/scheduler.py`
- Official issues:
  - #2788
  - #2990
  - #4595
  - #5209
  - #5861

## Executive conclusion

Current public wording around cron delivery over-promises continuity.

The highest-risk phrase is the user-doc claim that cron jobs can "deliver results back to the origin chat". Read literally, that sounds like "the result will come back into this same conversation and I can keep talking about it here". The actual contract is weaker:

- cron runs in a fresh / isolated session
- delivery is transport-level posting to a target chat/platform
- delivery is not mirrored into the main session history
- the main agent session is not aware of the cron run
- auto firing requires a running gateway ticker
- delivery can fail after successful execution
- some jobs hang before delivery, so successful execution is not guaranteed to produce a visible chat message

Official docs do contain some of these caveats, but they are late, fragmented, or buried in developer-facing material.

## What is misleading now

### 1) User feature page uses conversational wording without the non-conversational caveat up front

Official wording:
- `website/docs/user-guide/features/cron.md:18`
  - "deliver results back to the origin chat, local files, or configured platform targets"
- `website/docs/user-guide/features/cron.md:187`
  - `origin` = "Back to where the job was created"

Why this misleads:
- "back to the origin chat" reads like continuation of the current conversation.
- "Back to where the job was created" suggests chat-history continuity, not just target-address reuse.
- The crucial caveat appears later in response wrapping:
  - `website/docs/user-guide/features/cron.md:220`
    - "Note: The agent cannot see this message, and therefore cannot respond to it."
- That caveat is too late and too weak. It talks about the agent not seeing the message, but does not plainly say:
  - this will not appear as a normal continuation of the live chat/session
  - the main session will not gain awareness of the run
  - follow-up conversation does not automatically continue from the cron result

Related issue evidence:
- #2990 requests "conversational cron delivery" precisely because current cron output is not injected into normal conversation.
- #4595 states cron jobs execute in "completely isolated sessions" and are not observable by the main agent session.

Recommended wording fix:
- Replace line-18 style wording with:
  - "post results to the original platform/chat target, local files, or configured platform targets"
- Replace `origin` table wording with:
  - "Send a standalone scheduled message to the same platform/chat target the job was created from. This does not resume or append to the current live session history."

### 2) The only explicit "not in conversation history" statement is buried in developer docs

Official wording:
- `website/docs/developer-guide/cron-internals.md:187`
  - "Cron deliveries are NOT mirrored into gateway session conversation history. They exist only in the cron job's own session."

Why this matters:
- This is the clearest contract sentence in the official docs.
- But it is in a developer-internals page, not the main user-facing cron page.
- Users who only read user docs / use the tool schema never see the crucial behavioral contract.

Related issue evidence:
- #4595: main session cannot observe or interact with cron results.
- #2990: feature request exists specifically to add conversation injection.

Recommended doc structure fix:
- Promote this statement into the user feature page in a top-level "Important: cron delivery is not conversational" warning block near the first explanation of `deliver`.
- Keep the developer detail in internals, but do not rely on internals as the only source of truth for a user-visible contract.

Exact copy proposal:
- "Important: `deliver: origin` reuses the original chat target, but it does not append the result to your current Hermes session history. Cron runs in its own isolated session. The result is posted as a standalone scheduled message, not as a live continuation of this conversation."

### 3) Troubleshooting page repeats the ambiguous `origin` wording and understates failure visibility

Official wording:
- `website/docs/guides/cron-troubleshooting.md:71`
  - `origin` = "Delivers to the chat where the job was created"
- `website/docs/guides/cron-troubleshooting.md:75`
  - "If delivery fails, the job still runs — it just won't send anywhere. Check `hermes cron list` for updated `last_error` field (if available)."

Why this misleads:
- Again, "the chat where the job was created" sounds like session continuity.
- The delivery-failure guidance points users to `last_error`, but issue #5861 documents that delivery failures can still show `last_status = \"ok\"` and no useful persisted delivery error.
- So the page overstates observability of delivery failures.

Related issue evidence:
- #5861: silent cron delivery failures are reported as `ok`.
- #5209: jobs can hang after producing output and never reach delivery.

Recommended wording fix:
- Replace `origin` row with:
  - "Posts to the same platform/chat target used when the job was created. This is not added to the current session transcript."
- Replace delivery-failure guidance with something more accurate:
  - "A cron job can execute successfully yet still fail to deliver. Depending on Hermes version, delivery failures may be incomplete or missing in job status. If a message did not appear, verify gateway logs and the delivery target configuration instead of assuming `ok` means the message was posted."

### 4) Tool schema / tool description omits the critical non-conversational caveat

Official wording:
- `tools/cronjob_tools.py:425-427`
  - "The agent's final response is auto-delivered to the target. Put the primary user-facing content in the final response. Cron jobs run autonomously with no user present — they cannot ask questions or request clarification."
- `tools/cronjob_tools.py:459`
  - deliver description lists `origin`, `local`, platform targets, but does not explain what `origin` actually means in session terms.

Why this misleads:
- The tool description says auto-delivered, but not whether delivery is conversational, visible to the current agent, or persisted to the current session history.
- Agents therefore produce reassuring but false statements like the one shown in #2788:
  - "Delivery: local (you'll see the result here)"
- That false expectation is predictable because the tool contract does not contain the caveat.

Related issue evidence:
- #2788 includes an assistant promise that local delivery means "you'll see the result here", even though auto execution additionally required a gateway ticker and the result did not appear.
- #4595 and #2990 confirm lack of main-session observability / conversational continuity.

Recommended wording fix for schema notes:
- Add to schema description:
  - "Important: cron delivery is not conversational. `deliver='origin'` posts to the original chat target, but does not append to the current session history or trigger a follow-up agent reply. Cron runs in an isolated session."
- Expand `deliver` parameter description to:
  - "Delivery target. `origin` means: send a standalone scheduled message to the same platform/chat target used when the job was created. It does not resume the current chat session or write into the main session transcript. `local` means: save output only under `~/.hermes/cron/output/`."

### 5) Defaulting to `origin` when origin metadata exists increases surprise

Official wording / behavior:
- `cron/jobs.py:414-416`
  - "Default delivery to origin if available, otherwise local"

Why this misleads:
- On messaging platforms, users may never explicitly choose `origin`; the system silently defaults to it.
- If docs describe `origin` ambiguously, the default behavior reinforces the wrong mental model.

Inference (clearly labeled):
- Inference: even if the behavior itself stays the same, silent defaulting should be paired with explicit create-time copy so users understand they created an out-of-band scheduled post, not a future continuation of the same session.

Recommended UX copy fix:
- On create success, if `deliver=origin` because of defaulting, explicitly say so:
  - "Delivery: origin (default) — Hermes will post a standalone scheduled message to the original chat target. It will not resume this live session history."

### 6) Gateway / ticker prerequisite is real but easy to miss, which compounds the false expectation

Official wording:
- `website/docs/user-guide/features/cron.md:156`
  - "Cron execution is handled by the gateway daemon."
- `website/docs/guides/cron-troubleshooting.md:39-41`
  - cron jobs are fired by the gateway ticker; regular CLI chat does not automatically fire cron jobs
- `tools/cronjob_tools.py:496`
  - scheduler is "ticked by the gateway"
- `hermes_cli/cron.py:115-117`
  - CLI warns when gateway is not running

Why this still misleads in practice:
- The gateway/ticker requirement is present, but not embedded in the create success path where users form their expectation.
- #2788 shows the practical result: user believed the job was "running" and that they would see the result, but the next run never happened.

Recommended UX copy fix:
- Add a create-time postscript whenever no gateway is detected:
  - "Warning: no gateway/ticker is running on this machine. The job is saved, but it will not fire automatically until `hermes gateway` / `hermes serve` is running, or you manually run `hermes cron tick`."
- If gateway is running, say that too, but without overpromising result visibility:
  - "Gateway detected: the job can fire automatically. Delivery still happens as a standalone cron post, not as a continuation of this session."

### 7) Source comments are clearer than user-facing copy, but still describe `origin` as a chat rather than a transport target

Official wording:
- `cron/scheduler.py:201`
  - "Deliver job output to the configured target (origin chat, specific platform, etc.)."

Why this matters:
- Even internal wording uses "origin chat", which semantically nudges implementers and docs toward a conversational reading.
- Better contract language would consistently say "original platform/chat target" or "original delivery target".

Recommended wording fix:
- Replace "origin chat" with "original platform/chat target" in comments, docs, and UI where possible.

## Concrete wording replacements

### A) User guide opening bullets

Current
- "deliver results back to the origin chat, local files, or configured platform targets"

Replace with
- "post results to the original platform/chat target, local files, or configured platform targets"

Add immediately below
- "Important: posting to the original target is not conversational delivery. Cron output is sent from an isolated cron session and is not appended to your current live chat history."

### B) Delivery options table row for `origin`

Current
- "Back to where the job was created"

Replace with
- "Post a standalone scheduled message to the same platform/chat target the job was created from. Not added to the current session transcript."

### C) Response wrapping footer copy

Current
- "Note: The agent cannot see this message, and therefore cannot respond to it."

Replace with
- "Note: this scheduled message is not inserted into your live Hermes conversation. The cron run cannot see or continue the current session from this delivery."

Reason:
- Stronger, user-centered, and explicit about transcript/session behavior.

### D) Tool schema `deliver` description

Current
- lists supported values only

Replace with
- "Delivery target. `origin` posts a standalone scheduled message to the same platform/chat target used when the job was created; it does not resume the current chat session or append to the main session transcript. `local` saves output only to `~/.hermes/cron/output/`. Other values send to the named platform or explicit `platform:chat_id` target."

### E) Tool schema note block

Add
- "Cron delivery is transport-level, not conversational. The main agent session does not automatically observe, store, or reply to cron output. See issue #2990 / #4595 for requested conversational behavior that does not exist yet."

### F) Troubleshooting delivery section

Current
- "If delivery fails, the job still runs — it just won't send anywhere. Check `hermes cron list` for updated `last_error` field (if available)."

Replace with
- "A cron job can execute successfully and still fail to deliver. Depending on Hermes version, job status may not fully expose delivery failures. If no message appeared, check gateway logs and target configuration rather than assuming job status `ok` means the post reached the destination."

### G) CLI / tool success output when creating jobs

Current create output surfaces job id / schedule, but not the real delivery contract.

Recommended success copy for `deliver=origin`
- "Created job: <id>"
- "Delivery: origin — standalone scheduled post to the original platform/chat target"
- "Conversation: not added to this session history; no automatic follow-up reply"
- If gateway absent: "Not armed for automatic firing yet: start `hermes gateway` / `hermes serve`, or run `hermes cron tick` manually"

Recommended success copy for `deliver=local`
- "Delivery: local — output saved under ~/.hermes/cron/output/ only"
- "Conversation: nothing will appear in this chat automatically"

## Recommended doc structure changes

### 1) Add a top-level contract box near the top of the user cron page

Suggested heading:
- "Important: cron delivery is not a continuation of your live chat"

Contents:
- cron runs in an isolated session
- `origin` means original delivery target, not current session transcript
- main agent session does not observe or process cron output
- automatic firing requires a running gateway/ticker
- output may still fail to deliver even if execution succeeded

Why:
- This front-loads the real contract before examples and before the delivery table.

### 2) Split "delivery" into two concepts in docs

Current docs mix them:
- where the message is sent
- whether it becomes part of conversation state

Suggested structure:
- "Delivery target" section
- "Conversation visibility" section
- "Gateway/ticker requirement" section
- "Failure modes and observability" section

Why:
- Users currently map "sent to chat" => "visible in my active chat session". Separate sections prevent that conflation.

### 3) Link user docs directly to troubleshooting caveats

Add a short note in the user page under delivery:
- "No message appeared? See Cron Troubleshooting: gateway/ticker requirement, delivery failures, and silent suppression."

### 4) Move the strongest internals sentence into user docs verbatim

Promote the meaning of:
- "Cron deliveries are NOT mirrored into gateway session conversation history."

into user docs, simplified if needed.

## Recommended UX copy changes beyond docs

### 1) Creation confirmation should state all three of these explicitly
- firing mode: automatic only if gateway/ticker is running
- delivery mode: local vs platform/origin
- conversation mode: standalone post vs current transcript

### 2) `hermes cron list` should expose conversation semantics for `origin`

Suggested display field:
- "Conversation: standalone scheduled post (not in live session history)"

Inference:
- This is a UX recommendation derived from the documented confusion pattern; not an official current behavior statement.

### 3) Delivery failure status copy should stop implying observability is reliable

Until #5861 is fixed, avoid text like:
- "check job status to confirm delivery"

Prefer:
- "job status reflects execution, but delivery visibility may be incomplete; verify logs / destination when in doubt"

### 4) Timeout / hang messaging should mention that output file != delivered message

Based on #5209, if output was written locally but delivery never happened, copy should clearly distinguish:
- agent produced output
- scheduler received final completion
- delivery attempted
- delivery succeeded

## Evidence mapping to issues

- #2788: hidden gateway/ticker prerequisite + assistant overpromised that user would "see the result here"
- #2990: official feature request for conversational cron delivery proves current cron delivery is not conversational
- #4595: isolated sessions are not observable/interactable by the main agent session
- #5861: delivery can fail while status still appears `ok`, so docs should not imply reliable delivery observability
- #5209: job can hang after producing output and never reach delivery, so docs/UI must distinguish execution from delivery

## Bottom line

The contract should stop using "origin chat" as shorthand without qualification.

Best concise replacement:
- Use "original platform/chat target" for routing
- Explicitly say "not appended to the current live session history"
- Explicitly say "cron runs in an isolated session"
- Explicitly say "automatic firing requires a running gateway ticker"
- Explicitly say "successful execution and successful delivery are different states"
