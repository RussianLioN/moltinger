#!/usr/bin/env python3
"""
telegram-user-probe.py - Send probe message as Telegram user and validate bot reply.

Primary use-case:
  Continuous UAT from real user account:
  user -> bot -> verify reply quality/cleanliness.

Requires:
  pip install telethon

Required env or args:
  TELEGRAM_API_ID
  TELEGRAM_API_HASH
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import time
from typing import Optional


ERROR_PATTERNS = re.compile(r"traceback|exception|stack\s*trace|panic|internal server error", re.IGNORECASE)
SENSITIVE_PATTERNS = re.compile(r"\b(api[_ -]?key|token|password|secret)\b", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe bot as user and validate reply")
    parser.add_argument("--to", required=True, help="Target bot/chat (e.g. @moltinger_bot)")
    parser.add_argument("--text", default="/status", help="Probe message text")
    parser.add_argument("--timeout-seconds", type=int, default=45, help="Max wait for reply")
    parser.add_argument("--poll-interval", type=float, default=2.0, help="Polling interval seconds")
    parser.add_argument("--min-reply-len", type=int, default=2, help="Minimum acceptable reply length")
    parser.add_argument("--api-id", type=int, default=None, help="Telegram API ID")
    parser.add_argument("--api-hash", default=None, help="Telegram API hash")
    parser.add_argument(
        "--session",
        default=os.getenv("TELEGRAM_SESSION", ".telegram-user"),
        help="Telethon session file prefix (default: .telegram-user)",
    )
    parser.add_argument(
        "--env-file",
        default=".env",
        help="Optional env file with TELEGRAM_API_ID/TELEGRAM_API_HASH",
    )
    return parser.parse_args()


def load_env_file(path: str) -> None:
    if not path or not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = val


def fail(payload: dict, code: int = 1) -> int:
    payload.setdefault("ok", False)
    print(json.dumps(payload, ensure_ascii=False))
    return code


async def run(args: argparse.Namespace) -> int:
    try:
        from telethon import TelegramClient
    except ImportError:
        return fail(
            {
                "status": "fail",
                "error": "Missing dependency: telethon",
                "hint": "Install with: python3 -m pip install telethon",
            },
            1,
        )

    load_env_file(args.env_file)

    api_id = args.api_id or os.getenv("TELEGRAM_API_ID")
    api_hash = args.api_hash or os.getenv("TELEGRAM_API_HASH")

    if not api_id or not api_hash:
        return fail(
            {
                "status": "fail",
                "error": "TELEGRAM_API_ID and TELEGRAM_API_HASH are required",
            },
            2,
        )

    try:
        api_id_int = int(api_id)
    except (TypeError, ValueError):
        return fail({"status": "fail", "error": "TELEGRAM_API_ID must be an integer"}, 2)

    started_at = int(time.time())

    async with TelegramClient(args.session, api_id_int, api_hash) as client:
        entity = await client.get_entity(args.to)
        latest = await client.get_messages(entity, limit=1)
        before_id = latest[0].id if latest else 0

        sent = await client.send_message(entity=entity, message=args.text)
        sent_id = sent.id or 0
        cutoff_id = max(before_id, sent_id)

        deadline = time.monotonic() + max(1, args.timeout_seconds)
        reply_text: Optional[str] = None
        reply_id: Optional[int] = None

        while time.monotonic() < deadline:
            recent = await client.get_messages(entity, limit=10)
            for msg in reversed(recent):
                if not msg:
                    continue
                if (msg.id or 0) <= cutoff_id:
                    continue
                if msg.out:
                    continue
                text = (msg.raw_text or "").strip()
                if not text:
                    continue
                reply_text = text
                reply_id = msg.id
                break

            if reply_text is not None:
                break
            await asyncio.sleep(max(0.2, args.poll_interval))

    if reply_text is None:
        return fail(
            {
                "status": "fail",
                "error": "Timeout waiting for reply",
                "target": args.to,
                "sent_text": args.text,
                "timeout_seconds": args.timeout_seconds,
                "sent_message_id": sent_id,
                "timestamp": started_at,
            },
            3,
        )

    checks = {
        "non_empty": len(reply_text) > 0,
        "min_length": len(reply_text) >= max(1, args.min_reply_len),
        "error_signature_clean": ERROR_PATTERNS.search(reply_text) is None,
        "sensitive_signature_clean": SENSITIVE_PATTERNS.search(reply_text) is None,
    }

    failures = [name for name, ok in checks.items() if not ok]
    status = "pass" if not failures else "fail"
    ok = not failures

    print(
        json.dumps(
            {
                "ok": ok,
                "status": status,
                "target": args.to,
                "sent_text": args.text,
                "sent_message_id": sent_id,
                "reply_message_id": reply_id,
                "reply_text": reply_text,
                "checks": checks,
                "failures": failures,
                "timestamp": started_at,
            },
            ensure_ascii=False,
        )
    )
    return 0 if ok else 4


def main() -> int:
    args = parse_args()
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
