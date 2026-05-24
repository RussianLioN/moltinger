#!/usr/bin/env python3
"""Read-only Telegram channel collector for source-grounded research.

This helper is intentionally narrow:
- reads messages through an existing Telegram user session;
- never sends messages;
- writes raw results only to the requested output directory;
- prints no API hash, session string, phone number or cookies.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SECRET_URL_RE = re.compile(
    r"\b(?:vless|vmess|trojan|ss|ssr|hysteria|hy2|wireguard)://[^\s<>)]+",
    re.IGNORECASE,
)
TOKENISH_RE = re.compile(r"\b(?:api[_-]?hash|api[_-]?key|token|password|secret)=\S+", re.IGNORECASE)


@dataclass
class MessageRecord:
    source_mode: str
    query: str | None
    id: int
    date: str | None
    link: str | None
    text: str
    grouped_id: int | None
    reply_to_msg_id: int | None
    has_media: bool
    media_kind: str | None
    file_name: str | None
    mime_type: str | None
    file_size: int | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read Telegram channel messages through MTProto")
    parser.add_argument("--channel", default="routerich", help="Telegram channel/group username, without or with @")
    parser.add_argument("--query", action="append", default=[], help="Search query. Can be repeated.")
    parser.add_argument("--limit", type=int, default=30, help="Max messages per query")
    parser.add_argument(
        "--scan-limit",
        type=int,
        default=0,
        help="Optional latest-message scan limit without search. 0 disables full/latest scan.",
    )
    parser.add_argument(
        "--backfill-limit",
        type=int,
        default=0,
        help="Oldest-to-newest channel history batch size. 0 disables backfill.",
    )
    parser.add_argument(
        "--backfill-min-id",
        type=int,
        default=0,
        help="Exclusive lower message id for resumable forward backfill.",
    )
    parser.add_argument(
        "--backfill-max-id",
        type=int,
        default=0,
        help="Exclusive upper message id for bounded historical backfill. 0 means no upper bound.",
    )
    parser.add_argument(
        "--wait-time",
        type=float,
        default=None,
        help="Optional Telethon wait_time between history requests for large runs.",
    )
    parser.add_argument("--output-dir", required=True, help="Directory for raw and summary artifacts")
    parser.add_argument("--summary-limit", type=int, default=80, help="Max rows in Markdown summary")
    return parser.parse_args()


def redact_text(value: str) -> str:
    value = SECRET_URL_RE.sub("[REDACTED_PROXY_URL]", value)
    value = TOKENISH_RE.sub("[REDACTED_SECRET_ASSIGNMENT]", value)
    return value


def safe_snippet(value: str, limit: int = 700) -> str:
    value = " ".join(redact_text(value).split())
    if len(value) <= limit:
        return value
    return value[: limit - 1].rstrip() + "…"


def read_required_env() -> tuple[int, str, str]:
    api_id = os.getenv("TELEGRAM_TEST_API_ID") or os.getenv("TELEGRAM_API_ID")
    api_hash = os.getenv("TELEGRAM_TEST_API_HASH") or os.getenv("TELEGRAM_API_HASH")
    session = os.getenv("TELEGRAM_TEST_SESSION") or os.getenv("TELEGRAM_SESSION")

    missing = [
        name
        for name, value in (
            ("TELEGRAM_TEST_API_ID or TELEGRAM_API_ID", api_id),
            ("TELEGRAM_TEST_API_HASH or TELEGRAM_API_HASH", api_hash),
            ("TELEGRAM_TEST_SESSION or TELEGRAM_SESSION", session),
        )
        if not value
    ]
    if missing:
        raise SystemExit(
            json.dumps(
                {
                    "status": "precondition_failed",
                    "missing": missing,
                    "message": "Required Telegram MTProto environment is incomplete.",
                },
                ensure_ascii=False,
            )
        )

    try:
        api_id_int = int(str(api_id))
    except ValueError as exc:
        raise SystemExit(
            json.dumps(
                {
                    "status": "precondition_failed",
                    "message": "Telegram API ID must be an integer.",
                },
                ensure_ascii=False,
            )
        ) from exc

    return api_id_int, str(api_hash), str(session)


def normalize_channel(value: str) -> str:
    value = value.strip()
    if not value:
        raise SystemExit("channel cannot be empty")
    if value.startswith("https://t.me/"):
        value = value.rsplit("/", 1)[-1]
    return value[1:] if value.startswith("@") else value


def message_link(username: str | None, message_id: int) -> str | None:
    if not username:
        return None
    return f"https://t.me/{username}/{message_id}"


def media_info(message: Any) -> tuple[str | None, str | None, str | None, int | None]:
    if not getattr(message, "media", None):
        return None, None, None, None
    kind = message.media.__class__.__name__
    document = getattr(message, "document", None)
    if document is None:
        return kind, None, None, None

    file_name = None
    for attr in getattr(document, "attributes", []) or []:
        candidate = getattr(attr, "file_name", None)
        if candidate:
            file_name = candidate
            break
    return kind, file_name, getattr(document, "mime_type", None), getattr(document, "size", None)


def to_record(source_mode: str, query: str | None, username: str | None, message: Any) -> MessageRecord:
    raw_text = getattr(message, "raw_text", None) or ""
    kind, file_name, mime_type, file_size = media_info(message)
    dt = getattr(message, "date", None)
    if isinstance(dt, datetime):
        date_value = dt.astimezone(timezone.utc).isoformat()
    else:
        date_value = None
    message_id = int(getattr(message, "id", 0) or 0)
    return MessageRecord(
        source_mode=source_mode,
        query=query,
        id=message_id,
        date=date_value,
        link=message_link(username, message_id),
        text=redact_text(raw_text),
        grouped_id=getattr(message, "grouped_id", None),
        reply_to_msg_id=getattr(message, "reply_to_msg_id", None),
        has_media=bool(getattr(message, "media", None)),
        media_kind=kind,
        file_name=file_name,
        mime_type=mime_type,
        file_size=file_size,
    )


def write_jsonl(path: Path, records: list[MessageRecord]) -> None:
    with path.open("w", encoding="utf-8") as fh:
        for record in records:
            fh.write(json.dumps(asdict(record), ensure_ascii=False, sort_keys=True))
            fh.write("\n")


def write_summary(path: Path, *, channel: str, username: str | None, records: list[MessageRecord], args: argparse.Namespace) -> None:
    by_query: dict[str, int] = {}
    by_mode: dict[str, int] = {}
    for record in records:
        by_query[record.query or f"({record.source_mode})"] = by_query.get(record.query or f"({record.source_mode})", 0) + 1
        by_mode[record.source_mode] = by_mode.get(record.source_mode, 0) + 1
    message_ids = sorted(record.id for record in records if record.id)
    dates = sorted(record.date for record in records if record.date)

    lines = [
        "# Telegram Channel Collection Summary",
        "",
        f"- Generated at: {datetime.now(timezone.utc).isoformat()}",
        f"- Channel request: `{channel}`",
        f"- Resolved username: `{username or 'unknown'}`",
        f"- Search queries: {', '.join(f'`{q}`' for q in args.query) if args.query else 'none'}",
        f"- Per-query limit: `{args.limit}`",
        f"- Latest scan limit: `{args.scan_limit}`",
        f"- Backfill limit: `{args.backfill_limit}`",
        f"- Backfill min id: `{args.backfill_min_id}`",
        f"- Backfill max id: `{args.backfill_max_id}`",
        f"- Total records: `{len(records)}`",
    ]
    if message_ids:
        lines.append(f"- Message id range: `{message_ids[0]}` to `{message_ids[-1]}`.")
    backfill_ids = sorted(record.id for record in records if record.source_mode == "backfill" and record.id)
    if backfill_ids:
        lines.append(f"- Backfill checkpoint: next `--backfill-min-id {backfill_ids[-1]}`.")
    else:
        lines.append("- Backfill checkpoint: not available from this non-backfill artifact.")
    if dates:
        lines.append(f"- Message date range: `{dates[0]}` to `{dates[-1]}`.")
    lines.extend([
        "",
        "## Source Modes",
        "",
    ])
    for mode, count in sorted(by_mode.items()):
        lines.append(f"- `{mode}`: {count}")
    lines.extend([
        "",
        "## Counts",
        "",
    ])
    for query, count in sorted(by_query.items()):
        lines.append(f"- `{query}`: {count}")

    lines.extend(["", "## Evidence Rows", ""])
    for record in records[: max(0, args.summary_limit)]:
        media = ""
        if record.has_media:
            media = f"; media={record.media_kind or 'yes'}"
            if record.file_name:
                media += f"; file=`{record.file_name}`"
        lines.append(
            f"- mode=`{record.source_mode}` query=`{record.query or f'({record.source_mode})'}` id=`{record.id}` date=`{record.date or 'unknown'}` "
            f"link={record.link or 'n/a'}{media}: {safe_snippet(record.text)}"
        )

    if len(records) > args.summary_limit:
        lines.extend(["", f"_Summary truncated to {args.summary_limit} rows._"])

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


async def collect(args: argparse.Namespace) -> dict[str, Any]:
    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.sessions import StringSession  # type: ignore
    except Exception as exc:
        raise SystemExit(
            json.dumps(
                {
                    "status": "precondition_failed",
                    "message": "telethon is not installed",
                    "hint": "python3 -m pip install telethon",
                    "details": exc.__class__.__name__,
                },
                ensure_ascii=False,
            )
        ) from exc

    api_id, api_hash, session = read_required_env()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    channel = normalize_channel(args.channel)
    records: list[MessageRecord] = []

    async with TelegramClient(StringSession(session), api_id, api_hash) as client:
        entity = await client.get_entity(channel)
        username = getattr(entity, "username", None) or channel

        for query in args.query:
            async for message in client.iter_messages(
                entity,
                search=query,
                limit=max(1, args.limit),
                wait_time=args.wait_time,
            ):
                records.append(to_record("query", query, username, message))

        if args.scan_limit > 0:
            async for message in client.iter_messages(
                entity,
                limit=args.scan_limit,
                wait_time=args.wait_time,
            ):
                records.append(to_record("latest-scan", None, username, message))

        if args.backfill_limit > 0:
            backfill_kwargs: dict[str, Any] = {
                "limit": args.backfill_limit,
                "reverse": True,
                "wait_time": args.wait_time,
            }
            if args.backfill_min_id > 0:
                backfill_kwargs["min_id"] = args.backfill_min_id
            if args.backfill_max_id > 0:
                backfill_kwargs["max_id"] = args.backfill_max_id
            async for message in client.iter_messages(entity, **backfill_kwargs):
                records.append(to_record("backfill", None, username, message))

    raw_path = output_dir / "telegram-channel-records.ndjson"
    summary_path = output_dir / "telegram-channel-summary.md"
    meta_path = output_dir / "telegram-channel-meta.json"

    write_jsonl(raw_path, records)
    write_summary(summary_path, channel=channel, username=username, records=records, args=args)

    meta = {
        "status": "completed",
        "channel": channel,
        "resolved_username": username,
        "query_count": len(args.query),
        "record_count": len(records),
        "backfill_limit": args.backfill_limit,
        "backfill_min_id": args.backfill_min_id,
        "backfill_max_id": args.backfill_max_id,
        "min_message_id": min((record.id for record in records if record.id), default=None),
        "max_message_id": max((record.id for record in records if record.id), default=None),
        "min_backfill_message_id": min((record.id for record in records if record.source_mode == "backfill" and record.id), default=None),
        "max_backfill_message_id": max((record.id for record in records if record.source_mode == "backfill" and record.id), default=None),
        "raw_path": str(raw_path),
        "summary_path": str(summary_path),
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return meta


def main() -> int:
    args = parse_args()
    if not args.query and args.scan_limit <= 0 and args.backfill_limit <= 0:
        raise SystemExit("provide at least one --query, --scan-limit > 0 or --backfill-limit > 0")
    result = asyncio.run(collect(args))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
