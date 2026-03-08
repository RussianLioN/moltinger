#!/usr/bin/env python3
"""
Bootstrap Telegram StringSession for on-demand real_user E2E tests.

This helper performs one-time MTProto login (OTP + optional 2FA password)
and returns a StringSession that can be stored in TELEGRAM_TEST_SESSION.

Exit codes:
  0 completed
  2 precondition/config error
  4 upstream/auth/runtime error
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import json
import os
import stat
import sys
from dataclasses import dataclass
from typing import Any

EXIT_COMPLETED = 0
EXIT_PRECONDITION = 2
EXIT_UPSTREAM = 4


@dataclass
class BootstrapResult:
    status: str
    session: str | None
    session_preview: str | None
    error_code: str | None
    error_message: str | None
    context: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "session": self.session,
            "session_preview": self.session_preview,
            "error_code": self.error_code,
            "error_message": self.error_message,
            "context": self.context,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bootstrap TELEGRAM_TEST_SESSION via Telegram OTP login"
    )
    parser.add_argument("--api-id", required=True, help="Telegram API ID")
    parser.add_argument("--api-hash", required=True, help="Telegram API hash")
    parser.add_argument("--phone", required=True, help="Phone in international format, e.g. +79991234567")
    parser.add_argument("--code", help="OTP code from Telegram (optional; can also use TELEGRAM_TEST_OTP_CODE)")
    parser.add_argument(
        "--password",
        help="Telegram 2FA password (optional; can also use TELEGRAM_TEST_2FA_PASSWORD)",
    )
    parser.add_argument(
        "--session-out",
        help="Optional file path to write StringSession (chmod 600)",
    )
    parser.add_argument(
        "--print-session",
        action="store_true",
        help="Print raw session in JSON (unsafe for shared logs)",
    )
    parser.add_argument("--verbose", action="store_true", help="Verbose logs to stderr")
    return parser.parse_args()


def log(verbose: bool, message: str) -> None:
    if verbose:
        print(f"[telegram-bootstrap] {message}", file=sys.stderr)


def mask_session(value: str | None) -> str | None:
    if not value:
        return None
    if len(value) <= 12:
        return "***"
    return f"{value[:6]}...{value[-6:]}"


def mask_phone(value: str) -> str:
    digits = "".join(ch for ch in value if ch.isdigit())
    if len(digits) < 4:
        return "***"
    return f"***{digits[-4:]}"


def emit_and_exit(result: BootstrapResult, code: int) -> None:
    print(json.dumps(result.to_dict(), ensure_ascii=False))
    sys.exit(code)


def build_precondition(message: str, context: dict[str, Any] | None = None) -> BootstrapResult:
    return BootstrapResult(
        status="precondition_failed",
        session=None,
        session_preview=None,
        error_code="precondition",
        error_message=message,
        context=context or {},
    )


def build_upstream(message: str, context: dict[str, Any] | None = None) -> BootstrapResult:
    return BootstrapResult(
        status="upstream_failed",
        session=None,
        session_preview=None,
        error_code="upstream",
        error_message=message,
        context=context or {},
    )


async def run_bootstrap(args: argparse.Namespace) -> tuple[BootstrapResult, int]:
    try:
        api_id = int(str(args.api_id).strip())
    except ValueError:
        return build_precondition("api_id must be an integer"), EXIT_PRECONDITION

    api_hash = str(args.api_hash).strip()
    phone = str(args.phone).strip()
    code = str(args.code or os.getenv("TELEGRAM_TEST_OTP_CODE", "")).strip().replace(" ", "")
    password = str(args.password or os.getenv("TELEGRAM_TEST_2FA_PASSWORD", "")).strip()
    session_out = str(args.session_out or "").strip()

    if not api_hash:
        return build_precondition("api_hash is required"), EXIT_PRECONDITION
    if not phone:
        return build_precondition("phone is required"), EXIT_PRECONDITION
    if not session_out and not bool(args.print_session):
        return (
            build_precondition("Set --session-out or --print-session to receive session output"),
            EXIT_PRECONDITION,
        )

    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.errors import RPCError, SessionPasswordNeededError  # type: ignore
        from telethon.sessions import StringSession  # type: ignore
    except Exception:
        return (
            build_precondition(
                "telethon is not installed",
                {"hint": "Install dependency: python3 -m pip install telethon"},
            ),
            EXIT_PRECONDITION,
        )

    client = TelegramClient(StringSession(), api_id, api_hash, device_model="moltis-e2e-bootstrap")

    try:
        await client.connect()
        log(args.verbose, f"Requesting OTP for phone {mask_phone(phone)}")
        sent = await client.send_code_request(phone)

        if not code:
            if not sys.stdin.isatty():
                return (
                    build_precondition(
                        "OTP code is required (use --code or TELEGRAM_TEST_OTP_CODE)",
                        {"phone_masked": mask_phone(phone)},
                    ),
                    EXIT_PRECONDITION,
                )
            code = input("Enter Telegram OTP code: ").strip().replace(" ", "")

        if not code:
            return (
                build_precondition("OTP code cannot be empty", {"phone_masked": mask_phone(phone)}),
                EXIT_PRECONDITION,
            )

        try:
            await client.sign_in(phone=phone, code=code, phone_code_hash=sent.phone_code_hash)
        except SessionPasswordNeededError:
            if not password:
                if not sys.stdin.isatty():
                    return (
                        build_precondition(
                            "2FA password required (use --password or TELEGRAM_TEST_2FA_PASSWORD)",
                            {"phone_masked": mask_phone(phone)},
                        ),
                        EXIT_PRECONDITION,
                    )
                password = getpass.getpass("Enter Telegram 2FA password: ").strip()

            if not password:
                return (
                    build_precondition("2FA password cannot be empty", {"phone_masked": mask_phone(phone)}),
                    EXIT_PRECONDITION,
                )

            await client.sign_in(password=password)

        if not await client.is_user_authorized():
            return (
                build_upstream(
                    "Telegram authorization failed",
                    {"phone_masked": mask_phone(phone)},
                ),
                EXIT_UPSTREAM,
            )

        session_value = client.session.save()
        if not session_value:
            return build_upstream("failed to generate StringSession"), EXIT_UPSTREAM

        if session_out:
            with open(session_out, "w", encoding="utf-8") as f:
                f.write(session_value)
                f.write("\n")
            os.chmod(session_out, stat.S_IRUSR | stat.S_IWUSR)

        preview = mask_session(session_value)
        return (
            BootstrapResult(
                status="completed",
                session=session_value if bool(args.print_session) else None,
                session_preview=preview,
                error_code=None,
                error_message=None,
                context={
                    "phone_masked": mask_phone(phone),
                    "api_id": api_id,
                    "session_length": len(session_value),
                    "session_out": session_out or None,
                },
            ),
            EXIT_COMPLETED,
        )
    except RPCError as exc:
        return (
            build_upstream(
                f"telegram RPC error: {exc.__class__.__name__}",
                {"details": str(exc), "phone_masked": mask_phone(phone)},
            ),
            EXIT_UPSTREAM,
        )
    except Exception as exc:
        return (
            build_upstream(
                f"unexpected error: {exc.__class__.__name__}",
                {"details": str(exc), "phone_masked": mask_phone(phone)},
            ),
            EXIT_UPSTREAM,
        )
    finally:
        await client.disconnect()


def main() -> None:
    args = parse_args()
    result, code = asyncio.run(run_bootstrap(args))
    emit_and_exit(result, code)


if __name__ == "__main__":
    main()
