#!/usr/bin/env python3
"""Export Telegram API credentials as an encrypted local artifact.

Safety contract:
- reads credentials only from environment;
- never prints credential values;
- writes only encrypted artifacts and a non-secret result file.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path


def chmod_owner_only(path: Path) -> None:
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def write_json(path: Path, data: dict[str, object]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    chmod_owner_only(path)


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"missing required env: {name}")
    return value


def encrypt_file(plain_path: Path, public_key: Path, output_dir: Path) -> None:
    if not shutil.which("openssl"):
        raise RuntimeError("openssl is required for encrypted credential artifact")

    pass_path = output_dir / "telegram-credentials.pass"
    enc_path = output_dir / "telegram-credentials.env.enc"
    key_path = output_dir / "telegram-credentials.key.enc"
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
                str(plain_path),
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
        plain_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Export encrypted Telegram API credentials.")
    parser.add_argument("--public-key", type=Path, required=True, help="PEM public key for artifact encryption.")
    parser.add_argument("--output-dir", type=Path, required=True, help="Directory for encrypted artifact files.")
    args = parser.parse_args()

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / "telegram-credentials-result.json"
    plain_path = output_dir / "telegram-credentials.env"

    if not args.public_key.exists():
        write_json(result_path, {"status": "precondition_failed", "reason": "public key not found"})
        print("status: precondition_failed")
        print("reason: public key not found")
        return 2

    api_id = required_env("TELEGRAM_TEST_API_ID")
    api_hash = required_env("TELEGRAM_TEST_API_HASH")
    if not api_id.isdigit():
        write_json(result_path, {"status": "precondition_failed", "reason": "TELEGRAM_TEST_API_ID is invalid"})
        print("status: precondition_failed")
        print("reason: TELEGRAM_TEST_API_ID is invalid")
        return 2
    if len(api_hash) != 32:
        write_json(result_path, {"status": "precondition_failed", "reason": "TELEGRAM_TEST_API_HASH length is invalid"})
        print("status: precondition_failed")
        print("reason: TELEGRAM_TEST_API_HASH length is invalid")
        return 2

    plain_path.write_text(
        f"TELEGRAM_TEST_API_ID={api_id}\nTELEGRAM_TEST_API_HASH={api_hash}\n",
        encoding="utf-8",
    )
    chmod_owner_only(plain_path)
    encrypt_file(plain_path, args.public_key, output_dir)
    write_json(
        result_path,
        {
            "status": "completed",
            "artifact_files": ["telegram-credentials.env.enc", "telegram-credentials.key.enc"],
        },
    )
    print("status: completed")
    print("artifact: encrypted_credentials")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
