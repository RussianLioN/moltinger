#!/usr/bin/env python3
"""
Real-user Telegram E2E helper (MTProto).

Sends one message to a bot from a user session and waits for the bot reply.
Outputs a structured JSON payload to stdout and exits with:
  0 completed
  2 precondition/config error
  3 timeout
  4 upstream/auth/runtime error
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from dataclasses import dataclass
from typing import Any


EXIT_COMPLETED = 0
EXIT_PRECONDITION = 2
EXIT_TIMEOUT = 3
EXIT_UPSTREAM = 4


@dataclass
class RunResult:
    status: str
    observed_response: str | None
    error_code: str | None
    error_message: str | None
    context: dict[str, Any]
    transport: str = "telegram_mtproto_real_user"

    def to_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "observed_response": self.observed_response,
            "error_code": self.error_code,
            "error_message": self.error_message,
            "context": self.context,
            "transport": self.transport,
        }


def emit_and_exit(result: RunResult, code: int) -> None:
    print(json.dumps(result.to_dict(), ensure_ascii=False))
    sys.exit(code)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run real-user Telegram E2E probe via MTProto.")
    parser.add_argument("--api-id", required=True, help="Telegram API ID")
    parser.add_argument("--api-hash", required=True, help="Telegram API hash")
    parser.add_argument("--session", required=True, help="Telegram StringSession for test user")
    parser.add_argument("--bot-username", required=True, help="Target bot username, e.g. @moltinger_bot")
    parser.add_argument("--message", required=True, help="Message to send")
    parser.add_argument("--timeout-sec", type=int, default=30, help="Reply wait timeout in seconds")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logs to stderr")
    return parser.parse_args()


def normalize_username(value: str) -> str:
    value = value.strip()
    if not value:
        return value
    if value.startswith("@"):
        return value
    return f"@{value}"


def log(verbose: bool, message: str) -> None:
    if verbose:
        print(f"[telegram-real-user] {message}", file=sys.stderr)


async def run_probe(args: argparse.Namespace) -> tuple[RunResult, int]:
    if args.timeout_sec <= 0:
        return (
            RunResult(
                status="precondition_failed",
                observed_response=None,
                error_code="precondition",
                error_message="timeout must be positive",
                context={"timeout_sec": args.timeout_sec},
            ),
            EXIT_PRECONDITION,
        )

    try:
        api_id = int(str(args.api_id).strip())
    except ValueError:
        return (
            RunResult(
                status="precondition_failed",
                observed_response=None,
                error_code="precondition",
                error_message="api_id must be an integer",
                context={},
            ),
            EXIT_PRECONDITION,
        )

    api_hash = str(args.api_hash).strip()
    session = str(args.session).strip()
    message = str(args.message)
    bot_username = normalize_username(str(args.bot_username))

    if not api_hash or not session or not message.strip() or not bot_username:
        return (
            RunResult(
                status="precondition_failed",
                observed_response=None,
                error_code="precondition",
                error_message="api_hash, session, bot_username and message are required",
                context={},
            ),
            EXIT_PRECONDITION,
        )

    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.errors import RPCError  # type: ignore
        from telethon.sessions import StringSession  # type: ignore
    except Exception:
        return (
            RunResult(
                status="precondition_failed",
                observed_response=None,
                error_code="precondition",
                error_message="telethon is not installed",
                context={"hint": "Install dependency: pip install telethon"},
            ),
            EXIT_PRECONDITION,
        )

    client = TelegramClient(StringSession(session), api_id, api_hash, device_model="moltis-e2e")

    sent_message_id: int | None = None
    sent_chat_id: int | None = None
    bot_user_id: int | None = None
    bot_display: str | None = None
    poll_attempts = 0

    try:
        await client.connect()

        if not await client.is_user_authorized():
            return (
                RunResult(
                    status="precondition_failed",
                    observed_response=None,
                    error_code="precondition",
                    error_message="telegram session is not authorized",
                    context={"bot_username": bot_username},
                ),
                EXIT_PRECONDITION,
            )

        log(args.verbose, f"Resolving bot entity {bot_username}")
        bot_entity = await client.get_entity(bot_username)
        bot_user_id = getattr(bot_entity, "id", None)
        bot_display = getattr(bot_entity, "username", None) or bot_username

        log(args.verbose, "Sending test message")
        sent = await client.send_message(bot_entity, message)
        sent_message_id = getattr(sent, "id", None)
        sent_chat_id = getattr(sent, "chat_id", None)

        if sent_message_id is None:
            return (
                RunResult(
                    status="upstream_failed",
                    observed_response=None,
                    error_code="upstream",
                    error_message="failed to obtain sent message id",
                    context={"bot_username": bot_display},
                ),
                EXIT_UPSTREAM,
            )

        deadline = time.monotonic() + args.timeout_sec
        while time.monotonic() < deadline:
            poll_attempts += 1
            async for msg in client.iter_messages(bot_entity, limit=30):
                message_id = getattr(msg, "id", 0) or 0
                if message_id <= sent_message_id:
                    break

                sender_id = getattr(msg, "sender_id", None)
                is_outgoing = bool(getattr(msg, "out", False))
                if is_outgoing:
                    continue
                if bot_user_id is not None and sender_id != bot_user_id:
                    continue

                reply_text = (getattr(msg, "raw_text", None) or "").strip()
                if not reply_text:
                    reply_text = f"<non-text message id={message_id}>"

                return (
                    RunResult(
                        status="completed",
                        observed_response=reply_text,
                        error_code=None,
                        error_message=None,
                        context={
                            "bot_username": bot_display,
                            "bot_user_id": bot_user_id,
                            "chat_id": sent_chat_id,
                            "sent_message_id": sent_message_id,
                            "reply_message_id": message_id,
                            "poll_attempts": poll_attempts,
                        },
                    ),
                    EXIT_COMPLETED,
                )

            await asyncio.sleep(1.0)

        return (
            RunResult(
                status="timeout",
                observed_response=None,
                error_code="timeout",
                error_message="no bot reply before timeout",
                context={
                    "bot_username": bot_display,
                    "bot_user_id": bot_user_id,
                    "chat_id": sent_chat_id,
                    "sent_message_id": sent_message_id,
                    "poll_attempts": poll_attempts,
                },
            ),
            EXIT_TIMEOUT,
        )
    except RPCError as exc:
        return (
            RunResult(
                status="upstream_failed",
                observed_response=None,
                error_code="upstream",
                error_message=f"telegram RPC error: {exc.__class__.__name__}",
                context={
                    "bot_username": bot_username,
                    "details": str(exc),
                },
            ),
            EXIT_UPSTREAM,
        )
    except Exception as exc:
        return (
            RunResult(
                status="upstream_failed",
                observed_response=None,
                error_code="upstream",
                error_message=f"unexpected error: {exc.__class__.__name__}",
                context={"details": str(exc)},
            ),
            EXIT_UPSTREAM,
        )
    finally:
        await client.disconnect()


def main() -> None:
    args = parse_args()
    result, code = asyncio.run(run_probe(args))
    emit_and_exit(result, code)


if __name__ == "__main__":
    main()
