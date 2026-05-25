#!/usr/bin/env python3
"""Recover a Telegram MTProto StringSession through QR login.

Safety contract:
- reads Telegram API and bot credentials only from environment;
- sends the QR code through the configured Telegram bot chat;
- never prints or uploads the raw StringSession, API hash, bot token, or QR URL;
- stores only an encrypted session artifact for local decryption.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"missing required env: {name}")
    return value


def chmod_owner_only(path: Path) -> None:
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def write_json(path: Path, data: dict[str, object]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    chmod_owner_only(path)


def send_qr_document(bot_token: str, chat_id: str, document_path: Path, timeout_sec: int) -> None:
    boundary = f"----routerich-session-recovery-{secrets.token_hex(16)}"
    caption = (
        "Routerich MTProto session recovery QR.\n"
        "Open Telegram Settings -> Devices -> Link Desktop Device and scan this QR.\n"
        "Sent as an uncompressed PNG document; open it full-size before scanning.\n"
        f"Expires in about {timeout_sec} seconds."
    )

    def part(name: str, value: str) -> bytes:
        return (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n"
        ).encode("utf-8")

    body = bytearray()
    body.extend(part("chat_id", chat_id))
    body.extend(part("caption", caption))
    body.extend(
        (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="document"; filename="telegram-login-qr.png"\r\n'
            "Content-Type: image/png\r\n\r\n"
        ).encode("utf-8")
    )
    body.extend(document_path.read_bytes())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode("utf-8"))

    request = urllib.request.Request(
        f"https://api.telegram.org/bot{bot_token}/sendDocument",
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"Telegram bot sendDocument failed: HTTP {exc.code}: {details}") from exc

    if not payload.get("ok"):
        raise RuntimeError(f"Telegram bot sendDocument failed: {payload.get('description', 'unknown')}")


def send_login_link(bot_token: str, chat_id: str, login_url: str, timeout_sec: int) -> None:
    text = (
        "Routerich MTProto session recovery login.\n"
        "Tap the button below from your Telegram client. If the button does not open, "
        "copy the temporary link from this message and open it in Telegram.\n"
        f"Expires in about {timeout_sec} seconds.\n\n"
        f"{login_url}"
    )
    data = {
        "chat_id": chat_id,
        "text": text,
        "reply_markup": json.dumps(
            {"inline_keyboard": [[{"text": "Approve Telegram login", "url": login_url}]]},
            ensure_ascii=False,
        ),
        "disable_web_page_preview": "true",
    }
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        data=urllib.parse.urlencode(data).encode("utf-8"),
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"Telegram bot sendMessage failed: HTTP {exc.code}: {details}") from exc

    if not payload.get("ok"):
        raise RuntimeError(f"Telegram bot sendMessage failed: {payload.get('description', 'unknown')}")


def encrypt_session(session_path: Path, public_key: Path, output_dir: Path) -> None:
    if not shutil.which("openssl"):
        raise RuntimeError("openssl is required for encrypted session artifact")

    pass_path = output_dir / "telegram-session.pass"
    enc_path = output_dir / "telegram-session.enc"
    key_path = output_dir / "telegram-session.key.enc"
    pass_path.write_text(secrets.token_hex(32) + "\n", encoding="utf-8")
    chmod_owner_only(pass_path)

    try:
        subprocess.run(
            [
                "openssl",
                "enc",
                "-aes-256-cbc",
                "-pbkdf2",
                "-salt",
                "-in",
                str(session_path),
                "-out",
                str(enc_path),
                "-pass",
                f"file:{pass_path}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-encrypt",
                "-pubin",
                "-inkey",
                str(public_key),
                "-in",
                str(pass_path),
                "-out",
                str(key_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        chmod_owner_only(enc_path)
        chmod_owner_only(key_path)
    finally:
        pass_path.unlink(missing_ok=True)
        session_path.unlink(missing_ok=True)


async def recover(args: argparse.Namespace) -> int:
    try:
        from telethon import TelegramClient  # type: ignore
        from telethon.errors import RPCError, SessionPasswordNeededError  # type: ignore
        from telethon.sessions import StringSession  # type: ignore
        import qrcode  # type: ignore
    except Exception as exc:
        print(f"status: precondition_failed\nreason: missing dependency: {exc.__class__.__name__}")
        return 2

    api_id = int(required_env("TELEGRAM_TEST_API_ID"))
    api_hash = required_env("TELEGRAM_TEST_API_HASH")
    bot_token = required_env("TELEGRAM_BOT_TOKEN")
    chat_id = required_env("TELEGRAM_SESSION_RECOVERY_CHAT_ID")
    password_configured = bool(os.environ.get("TELEGRAM_TEST_2FA_PASSWORD", "").strip())

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / "recovery-result.json"
    qr_path = output_dir / "telegram-login-qr.png"
    session_path = output_dir / "telegram-session.plain"

    if not args.public_key.exists():
        write_json(result_path, {"status": "precondition_failed", "reason": "public key not found"})
        return 2
    if args.require_2fa_password and not password_configured:
        write_json(
            result_path,
            {
                "status": "precondition_failed",
                "reason": "TELEGRAM_TEST_2FA_PASSWORD is empty or unavailable",
            },
        )
        print("status: precondition_failed")
        print("reason: TELEGRAM_TEST_2FA_PASSWORD is empty or unavailable")
        return 2

    client = TelegramClient(StringSession(), api_id, api_hash, device_model="routerich-session-recovery")
    await client.connect()
    try:
        qr_login = await client.qr_login()
        send_login_link(bot_token, chat_id, qr_login.url, args.timeout_sec)
        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=18,
            border=6,
        )
        qr.add_data(qr_login.url)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        img.save(qr_path)
        chmod_owner_only(qr_path)
        send_qr_document(bot_token, chat_id, qr_path, args.timeout_sec)
        print("status: waiting_for_qr_approval")
        print("qr_delivery: telegram_bot_link_and_document")
        print(f"timeout_sec: {args.timeout_sec}")

        try:
            user = await qr_login.wait(timeout=args.timeout_sec)
        except asyncio.TimeoutError:
            write_json(result_path, {"status": "timeout", "reason": "qr approval timeout"})
            print("status: timeout")
            return 3
        except SessionPasswordNeededError:
            password = os.environ.get("TELEGRAM_TEST_2FA_PASSWORD", "").strip()
            if not password:
                write_json(result_path, {"status": "two_factor_required", "reason": "2FA password required"})
                print("status: two_factor_required")
                return 4
            try:
                user = await client.sign_in(password=password)
            except RPCError as exc:
                write_json(result_path, {"status": "upstream_failed", "reason": exc.__class__.__name__})
                print("status: upstream_failed")
                print(f"reason: {exc.__class__.__name__}")
                return 3
        except RPCError as exc:
            write_json(result_path, {"status": "upstream_failed", "reason": exc.__class__.__name__})
            print("status: upstream_failed")
            print(f"reason: {exc.__class__.__name__}")
            return 3

        session = client.session.save()
        session_path.write_text(session + "\n", encoding="utf-8")
        chmod_owner_only(session_path)
        encrypt_session(session_path, args.public_key, output_dir)
        qr_path.unlink(missing_ok=True)

        write_json(
            result_path,
            {
                "status": "completed",
                "user_id": getattr(user, "id", "unknown"),
                "username": getattr(user, "username", None) or "none",
                "session_length": len(session),
                "artifact_files": ["telegram-session.enc", "telegram-session.key.enc"],
            },
        )
        print("status: completed")
        print("artifact: encrypted_session")
        return 0
    finally:
        qr_path.unlink(missing_ok=True)
        await client.disconnect()


def main() -> int:
    parser = argparse.ArgumentParser(description="Recover encrypted Telegram MTProto StringSession.")
    parser.add_argument("--public-key", type=Path, required=True, help="PEM public key for artifact encryption.")
    parser.add_argument("--output-dir", type=Path, required=True, help="Directory for encrypted artifact files.")
    parser.add_argument("--timeout-sec", type=int, default=600, help="QR approval timeout.")
    parser.add_argument(
        "--require-2fa-password",
        action="store_true",
        help="Fail before QR delivery if TELEGRAM_TEST_2FA_PASSWORD is empty.",
    )
    return asyncio.run(recover(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
