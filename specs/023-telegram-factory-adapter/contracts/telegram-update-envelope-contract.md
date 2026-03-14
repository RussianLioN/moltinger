# Contract: Telegram Update Envelope

## Purpose

Define the minimum normalized shape for turning one real Telegram update into adapter input that can be routed toward the factory business-analyst runtime.

## Actors

- `business_user`: non-technical requester messaging the factory from Telegram
- `telegram_adapter`: transport/routing layer for the factory business-analyst agent
- `discovery_runtime`: existing channel-neutral discovery logic from `022`

## Required Inputs

- Telegram update identity (`update_id`)
- source chat identity (`chat_id`, `chat_type`)
- source user identity (`from_user_id`, display name when available)
- one user-visible payload (`message_text`, command text, or callback data)
- receive timestamp

## Required Outputs

- one normalized `TelegramUpdateEnvelope`
- one correlation-friendly adapter routing context
- one user-facing fallback response when the update cannot be handled

## Rules

- Unsupported update types must be rejected with a polite user-facing fallback instead of failing silently.
- The normalized envelope must preserve enough information to resume the same chat flow later.
- The adapter must sanitize transport metadata before passing it to user-facing replies.
- The envelope must be rich enough to derive a `TelegramIntent` and to locate the active project pointer.

## Failure Conditions

- a Telegram reply cannot be mapped to the right chat or user context
- the adapter loses the original update identity needed for deduplication or recovery
- unsupported updates disappear without a user-visible explanation
- raw webhook secrets, internal headers, or filesystem details leak into normalized output
