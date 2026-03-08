#!/usr/bin/env python3
"""
telegram-user-send.py - Send Telegram messages from a user account (MTProto).

Requires:
  pip install telethon

Environment:
  TELEGRAM_API_ID      Telegram API ID from https://my.telegram.org
  TELEGRAM_API_HASH    Telegram API hash from https://my.telegram.org
  TELEGRAM_SESSION     Optional session name/path (default: .telegram-user)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send Telegram message as user account")
    parser.add_argument("--to", required=True, help="Target username, phone, or chat ID")
    parser.add_argument("--text", required=True, help="Message text")
    parser.add_argument("--api-id", type=int, default=None, help="Telegram API ID")
    parser.add_argument("--api-hash", default=None, help="Telegram API hash")
    parser.add_argument(
        "--session",
        default=os.getenv("TELEGRAM_SESSION", ".telegram-user"),
        help="Session file prefix (default: .telegram-user)",
    )
    parser.add_argument(
        "--env-file",
        default=".env",
        help="Optional env file with TELEGRAM_API_ID/TELEGRAM_API_HASH (default: .env)",
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


async def run(args: argparse.Namespace) -> int:
    try:
        from telethon import TelegramClient
    except ImportError:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "Missing dependency: telethon",
                    "hint": "Install with: python3 -m pip install telethon",
                }
            )
        )
        return 1

    load_env_file(args.env_file)

    api_id = args.api_id or os.getenv("TELEGRAM_API_ID")
    api_hash = args.api_hash or os.getenv("TELEGRAM_API_HASH")

    if not api_id or not api_hash:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "TELEGRAM_API_ID and TELEGRAM_API_HASH are required",
                    "hint": "Set env vars or pass --api-id/--api-hash",
                }
            )
        )
        return 2

    try:
        api_id_int = int(api_id)
    except (TypeError, ValueError):
        print(json.dumps({"ok": False, "error": "TELEGRAM_API_ID must be an integer"}))
        return 2

    async with TelegramClient(args.session, api_id_int, api_hash) as client:
        # Telethon will request auth code/password interactively on first run.
        entity = await client.get_entity(args.to)
        sent = await client.send_message(entity=entity, message=args.text)

        print(
            json.dumps(
                {
                    "ok": True,
                    "to": args.to,
                    "message_id": sent.id,
                    "date": sent.date.isoformat() if sent.date else None,
                }
            )
        )
        return 0


def main() -> int:
    args = parse_args()
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
