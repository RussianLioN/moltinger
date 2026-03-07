#!/usr/bin/env python3
"""
Controlled MTProto CLI adapter for Telegram real-user operations.

Purpose:
- expose minimal, structured commands for LLM-driven E2E checks
- avoid direct raw session handling in prompts/logs

Exit codes:
  0 success
  2 precondition/config error
  3 timeout/no message observed
  4 upstream/auth/runtime error
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
from dataclasses import dataclass
from typing import Any

EXIT_OK = 0
EXIT_PRECONDITION = 2
EXIT_TIMEOUT = 3
EXIT_UPSTREAM = 4


@dataclass
class CliResult:
    status: str
    command: str
    data: dict[str, Any]
    error_code: str | None = None
    error_message: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "command": self.command,
            "data": self.data,
            "error_code": self.error_code,
            "error_message": self.error_message,
        }


def emit(result: CliResult, code: int) -> None:
    print(json.dumps(result.to_dict(), ensure_ascii=False))
    sys.exit(code)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Telegram real-user MTProto CLI adapter")
    parser.add_argument("--api-id", default=os.getenv("TELEGRAM_TEST_API_ID", ""), help="Telegram API ID")
    parser.add_argument("--api-hash", default=os.getenv("TELEGRAM_TEST_API_HASH", ""), help="Telegram API hash")
    parser.add_argument(
        "--session",
        default=os.getenv("TELEGRAM_TEST_SESSION", ""),
        help="Telegram StringSession",
    )
    parser.add_argument("--verbose", action="store_true", help="Verbose logs to stderr")

    sub = parser.add_subparsers(dest="command", required=True)

    p_resolve = sub.add_parser("resolve", help="Resolve target to Telegram entity metadata")
    p_resolve.add_argument("--target", required=True, help="@username, t.me link, phone, or numeric id")

    p_send = sub.add_parser("send", help="Send one message")
    p_send.add_argument("--to", required=True, help="Target entity")
    p_send.add_argument("--text", required=True, help="Message text")

    p_wait = sub.add_parser("reply-wait", help="Wait for incoming reply from target")
    p_wait.add_argument("--from", dest="from_target", required=True, help="Target entity")
    p_wait.add_argument("--after-message-id", type=int, default=0, help="Only accept message IDs greater than this")
    p_wait.add_argument("--timeout-sec", type=int, default=45, help="Timeout in seconds")
    p_wait.add_argument("--poll-interval-sec", type=float, default=1.0, help="Polling interval")

    p_list = sub.add_parser("list-dialogs", help="List dialogs")
    p_list.add_argument("--limit", type=int, default=20, help="Max dialogs")

    p_probe = sub.add_parser("probe", help="Send message and wait for reply")
    p_probe.add_argument("--to", required=True, help="Target entity")
    p_probe.add_argument("--text", required=True, help="Message text")
    p_probe.add_argument("--timeout-sec", type=int, default=45, help="Reply timeout")
    p_probe.add_argument("--poll-interval-sec", type=float, default=1.0, help="Polling interval")

    return parser.parse_args()


def log(verbose: bool, message: str) -> None:
    if verbose:
        print(f"[telegram-real-user-cli] {message}", file=sys.stderr)


def normalize_target(value: str) -> str:
    value = value.strip()
    if not value:
        return value
    if value.startswith("http://") or value.startswith("https://"):
        return value
    if value.startswith("@"):
        return value
    if value.lstrip("-").isdigit():
        return value
    return value


def sanitize_text(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    return text if text else None


async def run(args: argparse.Namespace) -> tuple[CliResult, int]:
    try:
        api_id = int(str(args.api_id).strip())
    except ValueError:
        return (
            CliResult(
                status="precondition_failed",
                command=args.command,
                data={},
                error_code="precondition",
                error_message="api_id must be an integer",
            ),
            EXIT_PRECONDITION,
        )

    api_hash = str(args.api_hash).strip()
    session = str(args.session).strip()

    if not api_hash or not session:
        return (
            CliResult(
                status="precondition_failed",
                command=args.command,
                data={
                    "missing": [
                        key
                        for key, val in {
                            "TELEGRAM_TEST_API_HASH": api_hash,
                            "TELEGRAM_TEST_SESSION": session,
                        }.items()
                        if not val
                    ]
                },
                error_code="precondition",
                error_message="missing TELEGRAM_TEST_API_HASH or TELEGRAM_TEST_SESSION",
            ),
            EXIT_PRECONDITION,
        )

    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.errors import RPCError  # type: ignore
        from telethon.sessions import StringSession  # type: ignore
    except Exception:
        return (
            CliResult(
                status="precondition_failed",
                command=args.command,
                data={"hint": "Install dependency: python3 -m pip install telethon"},
                error_code="precondition",
                error_message="telethon is not installed",
            ),
            EXIT_PRECONDITION,
        )

    client = TelegramClient(StringSession(session), api_id, api_hash, device_model="moltis-e2e-cli")

    try:
        await client.connect()
        if not await client.is_user_authorized():
            return (
                CliResult(
                    status="precondition_failed",
                    command=args.command,
                    data={},
                    error_code="precondition",
                    error_message="telegram session is not authorized",
                ),
                EXIT_PRECONDITION,
            )

        if args.command == "resolve":
            target = normalize_target(args.target)
            entity = await client.get_entity(target)
            data = {
                "target": target,
                "entity_id": getattr(entity, "id", None),
                "username": getattr(entity, "username", None),
                "title": getattr(entity, "title", None),
                "phone": getattr(entity, "phone", None),
                "entity_type": entity.__class__.__name__,
            }
            return CliResult(status="completed", command=args.command, data=data), EXIT_OK

        if args.command == "send":
            target = normalize_target(args.to)
            text = str(args.text)
            if not text.strip():
                return (
                    CliResult(
                        status="precondition_failed",
                        command=args.command,
                        data={},
                        error_code="precondition",
                        error_message="text must be non-empty",
                    ),
                    EXIT_PRECONDITION,
                )

            entity = await client.get_entity(target)
            msg = await client.send_message(entity, text)
            data = {
                "target": target,
                "peer_id": getattr(entity, "id", None),
                "message_id": getattr(msg, "id", None),
                "date": str(getattr(msg, "date", "")),
            }
            return CliResult(status="completed", command=args.command, data=data), EXIT_OK

        if args.command == "reply-wait":
            if args.timeout_sec <= 0 or args.poll_interval_sec <= 0:
                return (
                    CliResult(
                        status="precondition_failed",
                        command=args.command,
                        data={},
                        error_code="precondition",
                        error_message="timeout_sec and poll_interval_sec must be positive",
                    ),
                    EXIT_PRECONDITION,
                )

            target = normalize_target(args.from_target)
            entity = await client.get_entity(target)
            peer_id = getattr(entity, "id", None)
            deadline = time.monotonic() + int(args.timeout_sec)
            polls = 0

            while time.monotonic() < deadline:
                polls += 1
                async for msg in client.iter_messages(entity, limit=30):
                    message_id = int(getattr(msg, "id", 0) or 0)
                    if message_id <= int(args.after_message_id):
                        break

                    if bool(getattr(msg, "out", False)):
                        continue

                    sender_id = getattr(msg, "sender_id", None)
                    if peer_id is not None and sender_id not in (peer_id, None):
                        continue

                    text = sanitize_text(getattr(msg, "raw_text", None))
                    if text is None:
                        text = f"<non-text message id={message_id}>"

                    return (
                        CliResult(
                            status="completed",
                            command=args.command,
                            data={
                                "target": target,
                                "peer_id": peer_id,
                                "reply_message_id": message_id,
                                "sender_id": sender_id,
                                "reply_text": text,
                                "polls": polls,
                            },
                        ),
                        EXIT_OK,
                    )

                await asyncio.sleep(float(args.poll_interval_sec))

            return (
                CliResult(
                    status="timeout",
                    command=args.command,
                    data={
                        "target": target,
                        "after_message_id": int(args.after_message_id),
                        "polls": polls,
                    },
                    error_code="timeout",
                    error_message="no reply before timeout",
                ),
                EXIT_TIMEOUT,
            )

        if args.command == "list-dialogs":
            if args.limit <= 0:
                return (
                    CliResult(
                        status="precondition_failed",
                        command=args.command,
                        data={},
                        error_code="precondition",
                        error_message="limit must be positive",
                    ),
                    EXIT_PRECONDITION,
                )

            dialogs = []
            async for dialog in client.iter_dialogs(limit=int(args.limit)):
                entity = dialog.entity
                dialogs.append(
                    {
                        "id": getattr(entity, "id", None),
                        "name": getattr(dialog, "name", None),
                        "username": getattr(entity, "username", None),
                        "is_user": bool(getattr(dialog, "is_user", False)),
                        "is_group": bool(getattr(dialog, "is_group", False)),
                        "is_channel": bool(getattr(dialog, "is_channel", False)),
                    }
                )

            return (
                CliResult(
                    status="completed",
                    command=args.command,
                    data={"limit": int(args.limit), "dialogs": dialogs},
                ),
                EXIT_OK,
            )

        if args.command == "probe":
            if args.timeout_sec <= 0 or args.poll_interval_sec <= 0:
                return (
                    CliResult(
                        status="precondition_failed",
                        command=args.command,
                        data={},
                        error_code="precondition",
                        error_message="timeout_sec and poll_interval_sec must be positive",
                    ),
                    EXIT_PRECONDITION,
                )

            target = normalize_target(args.to)
            text = str(args.text)
            if not text.strip():
                return (
                    CliResult(
                        status="precondition_failed",
                        command=args.command,
                        data={},
                        error_code="precondition",
                        error_message="text must be non-empty",
                    ),
                    EXIT_PRECONDITION,
                )

            entity = await client.get_entity(target)
            peer_id = getattr(entity, "id", None)

            log(args.verbose, f"Sending probe message to {target}")
            sent = await client.send_message(entity, text)
            sent_id = int(getattr(sent, "id", 0) or 0)

            deadline = time.monotonic() + int(args.timeout_sec)
            polls = 0

            while time.monotonic() < deadline:
                polls += 1
                async for msg in client.iter_messages(entity, limit=30):
                    message_id = int(getattr(msg, "id", 0) or 0)
                    if message_id <= sent_id:
                        break

                    if bool(getattr(msg, "out", False)):
                        continue

                    sender_id = getattr(msg, "sender_id", None)
                    if peer_id is not None and sender_id not in (peer_id, None):
                        continue

                    reply_text = sanitize_text(getattr(msg, "raw_text", None))
                    if reply_text is None:
                        reply_text = f"<non-text message id={message_id}>"

                    return (
                        CliResult(
                            status="completed",
                            command=args.command,
                            data={
                                "target": target,
                                "peer_id": peer_id,
                                "sent_message_id": sent_id,
                                "reply_message_id": message_id,
                                "reply_text": reply_text,
                                "polls": polls,
                            },
                        ),
                        EXIT_OK,
                    )

                await asyncio.sleep(float(args.poll_interval_sec))

            return (
                CliResult(
                    status="timeout",
                    command=args.command,
                    data={
                        "target": target,
                        "peer_id": peer_id,
                        "sent_message_id": sent_id,
                        "polls": polls,
                    },
                    error_code="timeout",
                    error_message="no reply before timeout",
                ),
                EXIT_TIMEOUT,
            )

        return (
            CliResult(
                status="precondition_failed",
                command=args.command,
                data={},
                error_code="precondition",
                error_message=f"unsupported command: {args.command}",
            ),
            EXIT_PRECONDITION,
        )

    except RPCError as exc:
        return (
            CliResult(
                status="upstream_failed",
                command=args.command,
                data={},
                error_code="upstream",
                error_message=f"telegram RPC error: {exc.__class__.__name__}",
            ),
            EXIT_UPSTREAM,
        )
    except Exception as exc:
        return (
            CliResult(
                status="upstream_failed",
                command=args.command,
                data={},
                error_code="upstream",
                error_message=f"unexpected error: {exc.__class__.__name__}",
            ),
            EXIT_UPSTREAM,
        )
    finally:
        await client.disconnect()


def main() -> None:
    args = parse_args()
    result, code = asyncio.run(run(args))
    emit(result, code)


if __name__ == "__main__":
    main()
