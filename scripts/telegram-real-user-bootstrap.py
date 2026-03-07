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
    parser.add_argument(
        "--login-mode",
        choices=["otp", "qr"],
        default="otp",
        help="Authorization mode: otp (default) or qr",
    )
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
    parser.add_argument(
        "--qr-timeout-sec",
        type=int,
        default=180,
        help="QR login wait timeout in seconds (default: 180)",
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
    login_mode = str(args.login_mode).strip()
    code = str(args.code or os.getenv("TELEGRAM_TEST_OTP_CODE", "")).strip().replace(" ", "")
    password = str(args.password or os.getenv("TELEGRAM_TEST_2FA_PASSWORD", "")).strip()
    session_out = str(args.session_out or "").strip()

    if not api_hash:
        return build_precondition("api_hash is required"), EXIT_PRECONDITION
    if not phone:
        return build_precondition("phone is required"), EXIT_PRECONDITION
    if login_mode not in {"otp", "qr"}:
        return build_precondition("login_mode must be otp or qr"), EXIT_PRECONDITION
    if args.qr_timeout_sec <= 0:
        return build_precondition("qr_timeout_sec must be positive"), EXIT_PRECONDITION
    if not session_out and not bool(args.print_session):
        return (
            build_precondition("Set --session-out or --print-session to receive session output"),
            EXIT_PRECONDITION,
        )

    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.errors import (  # type: ignore
            PhoneCodeExpiredError,
            PhoneCodeInvalidError,
            RPCError,
            SessionPasswordNeededError,
        )
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
        sent_type: str | None = None
        sent_next_type: str | None = None
        sent_timeout: int | None = None
        code_attempts = 0
        resend_attempts = 0
        qr_wait_timeout: int | None = None

        if login_mode == "qr":
            log(args.verbose, f"Requesting QR login for phone {mask_phone(phone)}")
            qr_login = await client.qr_login()
            qr_wait_timeout = int(args.qr_timeout_sec)

            if not sys.stdin.isatty():
                return (
                    build_precondition(
                        "qr login mode requires interactive terminal",
                        {"phone_masked": mask_phone(phone), "login_mode": login_mode},
                    ),
                    EXIT_PRECONDITION,
                )

            print(
                (
                    "QR login URL (open it on another screen and confirm in Telegram -> "
                    "Settings -> Devices -> Link Desktop Device):\n"
                    f"{qr_login.url}"
                ),
                file=sys.stderr,
            )

            try:
                await qr_login.wait(timeout=float(qr_wait_timeout))
            except asyncio.TimeoutError:
                return (
                    build_upstream(
                        "qr login timed out",
                        {
                            "phone_masked": mask_phone(phone),
                            "login_mode": login_mode,
                            "qr_timeout_sec": qr_wait_timeout,
                        },
                    ),
                    EXIT_UPSTREAM,
                )
            except SessionPasswordNeededError:
                if not password:
                    password = getpass.getpass("Enter Telegram 2FA password: ").strip()
                if not password:
                    return (
                        build_precondition("2FA password cannot be empty", {"phone_masked": mask_phone(phone)}),
                        EXIT_PRECONDITION,
                    )
                await client.sign_in(password=password)
        else:
            log(args.verbose, f"Requesting OTP for phone {mask_phone(phone)}")
            sent = await client.send_code_request(phone)
            sent_type = sent.type.__class__.__name__ if getattr(sent, "type", None) else None
            sent_next_type = sent.next_type.__class__.__name__ if getattr(sent, "next_type", None) else None
            sent_timeout = getattr(sent, "timeout", None)

            log(
                args.verbose,
                (
                    "OTP delivery details: "
                    f"type={sent_type or 'unknown'}, next_type={sent_next_type or 'none'}, "
                    f"timeout={sent_timeout}"
                ),
            )

            while True:
                if not code:
                    if not sys.stdin.isatty():
                        return (
                            build_precondition(
                                "OTP code is required (use --code or TELEGRAM_TEST_OTP_CODE)",
                                {
                                    "phone_masked": mask_phone(phone),
                                    "sent_type": sent_type,
                                    "next_type": sent_next_type,
                                    "timeout": sent_timeout,
                                },
                            ),
                            EXIT_PRECONDITION,
                        )
                    code = input("Enter Telegram OTP code (or /resend): ").strip().replace(" ", "")

                if not code:
                    return (
                        build_precondition(
                            "OTP code cannot be empty",
                            {
                                "phone_masked": mask_phone(phone),
                                "sent_type": sent_type,
                                "next_type": sent_next_type,
                                "timeout": sent_timeout,
                            },
                        ),
                        EXIT_PRECONDITION,
                    )

                if code.lower() == "/resend":
                    resend_attempts += 1
                    log(args.verbose, "Resending OTP code")
                    sent = await client.send_code_request(phone)
                    sent_type = sent.type.__class__.__name__ if getattr(sent, "type", None) else None
                    sent_next_type = sent.next_type.__class__.__name__ if getattr(sent, "next_type", None) else None
                    sent_timeout = getattr(sent, "timeout", None)
                    log(
                        args.verbose,
                        (
                            "OTP resend details: "
                            f"type={sent_type or 'unknown'}, next_type={sent_next_type or 'none'}, "
                            f"timeout={sent_timeout}"
                        ),
                    )
                    code = ""
                    continue

                code_attempts += 1
                try:
                    await client.sign_in(phone=phone, code=code, phone_code_hash=sent.phone_code_hash)
                    break
                except PhoneCodeInvalidError:
                    if not sys.stdin.isatty():
                        return (
                            build_upstream(
                                "telegram RPC error: PhoneCodeInvalidError",
                                {
                                    "details": "The phone code entered was invalid",
                                    "phone_masked": mask_phone(phone),
                                    "code_attempts": code_attempts,
                                    "resend_attempts": resend_attempts,
                                    "sent_type": sent_type,
                                },
                            ),
                            EXIT_UPSTREAM,
                        )
                    print("Invalid OTP code. Try again or enter /resend.", file=sys.stderr)
                    code = ""
                    continue
                except PhoneCodeExpiredError:
                    if not sys.stdin.isatty():
                        return (
                            build_upstream(
                                "telegram RPC error: PhoneCodeExpiredError",
                                {
                                    "details": "The phone code has expired",
                                    "phone_masked": mask_phone(phone),
                                    "code_attempts": code_attempts,
                                    "resend_attempts": resend_attempts,
                                    "sent_type": sent_type,
                                },
                            ),
                            EXIT_UPSTREAM,
                        )
                    print("OTP code expired. Enter /resend to request a new code.", file=sys.stderr)
                    code = ""
                    continue
                except SessionPasswordNeededError:
                    if not password:
                        if not sys.stdin.isatty():
                            return (
                                build_precondition(
                                    "2FA password required (use --password or TELEGRAM_TEST_2FA_PASSWORD)",
                                    {
                                        "phone_masked": mask_phone(phone),
                                        "code_attempts": code_attempts,
                                        "resend_attempts": resend_attempts,
                                    },
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
                    break

        if not await client.is_user_authorized():
            return (
                build_upstream(
                    "Telegram authorization failed",
                    {
                        "phone_masked": mask_phone(phone),
                        "login_mode": login_mode,
                        "sent_type": sent_type,
                        "next_type": sent_next_type,
                        "timeout": sent_timeout,
                    },
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
                    "login_mode": login_mode,
                    "qr_timeout_sec": qr_wait_timeout,
                    "sent_type": sent_type,
                    "next_type": sent_next_type,
                    "timeout": sent_timeout,
                    "code_attempts": code_attempts,
                    "resend_attempts": resend_attempts,
                },
            ),
            EXIT_COMPLETED,
        )
    except RPCError as exc:
        return (
            build_upstream(
                f"telegram RPC error: {exc.__class__.__name__}",
                {"details": str(exc), "phone_masked": mask_phone(phone), "login_mode": login_mode},
            ),
            EXIT_UPSTREAM,
        )
    except Exception as exc:
        return (
            build_upstream(
                f"unexpected error: {exc.__class__.__name__}",
                {"details": str(exc), "phone_masked": mask_phone(phone), "login_mode": login_mode},
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
