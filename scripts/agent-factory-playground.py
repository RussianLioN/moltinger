#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import tarfile
import textwrap
from pathlib import Path
from typing import Any

from agent_factory_common import (
    load_json,
    normalize_text,
    slugify,
    utc_now,
    write_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a runnable playground bundle for one swarm run.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    package = subparsers.add_parser("package", help="Package one swarm run into a playground bundle")
    package.add_argument("--swarm-run", required=True, help="Path to swarm-run JSON or fixture JSON")
    package.add_argument("--output-dir", required=True, help="Directory where the playground bundle should be written")
    package.add_argument("--container-ref", help="Optional container reference override")
    package.add_argument("--evidence-bundle-ref", help="Optional evidence bundle reference override")
    package.add_argument("--output", help="Optional JSON summary output path")

    return parser.parse_args()


def default_container_ref(concept_id: str, concept_version: str) -> str:
    return f"ghcr.io/russianlion/{slugify(concept_id, 'agent-factory')}:{concept_version}-playground"


def ensure_swarm_source(payload: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    swarm_run = payload.get("swarm_run", {})
    stage_executions = payload.get("stage_executions", [])
    playground_package = payload.get("playground_package", {})
    if not isinstance(swarm_run, dict):
        raise ValueError("swarm_run must be an object")
    if not isinstance(stage_executions, list):
        raise ValueError("stage_executions must be a list")
    if not isinstance(playground_package, dict):
        raise ValueError("playground_package must be an object when present")
    return swarm_run, [item for item in stage_executions if isinstance(item, dict)], playground_package


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def build_synthetic_dataset(concept_id: str, concept_version: str) -> dict[str, Any]:
    return {
        "dataset_id": f"synthetic-{slugify(f'{concept_id}-{concept_version}', 'dataset')}",
        "data_profile": "synthetic",
        "records": [
            {
                "case_id": "demo-001",
                "input": "Пользователь описывает идею автоматизации через Telegram intake.",
                "expected_outcome": "Формируется concept pack и запускается review loop без production deploy.",
            },
            {
                "case_id": "demo-002",
                "input": "Одобренная концепция передается в internal swarm.",
                "expected_outcome": "Playground bundle готов к демонстрации на тестовых данных.",
            },
        ],
    }


def build_server_source() -> str:
    return textwrap.dedent(
        """
        import json
        import os
        from http.server import BaseHTTPRequestHandler, HTTPServer

        APP_DIR = os.path.dirname(__file__)
        with open(os.path.join(APP_DIR, "playground-card.json"), "r", encoding="utf-8") as fh:
            PLAYGROUND_CARD = json.load(fh)
        with open(os.path.join(APP_DIR, "synthetic-dataset.json"), "r", encoding="utf-8") as fh:
            SYNTHETIC_DATASET = json.load(fh)

        class Handler(BaseHTTPRequestHandler):
            def _send_json(self, payload):
                body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if self.path in ("/", "/card"):
                    self._send_json(PLAYGROUND_CARD)
                    return
                if self.path == "/data":
                    self._send_json(SYNTHETIC_DATASET)
                    return
                self.send_response(404)
                self.end_headers()

        if __name__ == "__main__":
            server = HTTPServer(("0.0.0.0", 8080), Handler)
            server.serve_forever()
        """
    ).strip()


def build_dockerfile() -> str:
    return textwrap.dedent(
        """
        FROM python:3.11-slim
        WORKDIR /app
        COPY playground_server.py /app/playground_server.py
        COPY playground-card.json /app/playground-card.json
        COPY synthetic-dataset.json /app/synthetic-dataset.json
        EXPOSE 8080
        CMD ["python", "/app/playground_server.py"]
        """
    ).strip()


def build_launch_instructions(container_ref: str, archive_name: str) -> str:
    return textwrap.dedent(
        f"""
        # Launch Instructions

        ## Local demo flow

        1. Распаковать bundle archive `{archive_name}`.
        2. Перейти в каталог `playground-bundle/`.
        3. Собрать контейнер:

        ```bash
        docker build -t {container_ref} .
        ```

        4. Запустить playground:

        ```bash
        docker run --rm -p 18080:8080 {container_ref}
        ```

        5. Проверить ответы:
        - `GET http://localhost:18080/`
        - `GET http://localhost:18080/data`
        """
    ).strip()


def package_playground(args: argparse.Namespace) -> int:
    payload = load_json(args.swarm_run)
    if not isinstance(payload, dict):
        raise ValueError("swarm-run source must be a JSON object")

    swarm_run, stage_executions, source_playground = ensure_swarm_source(payload)
    concept_id = normalize_text(swarm_run.get("concept_id"))
    concept_version = normalize_text(swarm_run.get("concept_version"))
    swarm_run_id = normalize_text(swarm_run.get("swarm_run_id"))
    if not concept_id or not concept_version or not swarm_run_id:
        raise ValueError("swarm_run must include swarm_run_id, concept_id, and concept_version")

    output_dir = Path(args.output_dir)
    bundle_dir = output_dir / "playground-bundle"
    bundle_dir.mkdir(parents=True, exist_ok=True)

    container_ref = normalize_text(args.container_ref) or normalize_text(source_playground.get("container_ref")) or default_container_ref(concept_id, concept_version)
    evidence_bundle_ref = normalize_text(args.evidence_bundle_ref) or normalize_text(source_playground.get("evidence_bundle_ref")) or str(output_dir / "artifacts" / "evidence" / "bundle-manifest.json")
    review_status = normalize_text(source_playground.get("review_status")) or "ready_for_demo"
    generated_at = utc_now()

    synthetic_dataset = build_synthetic_dataset(concept_id, concept_version)
    playground_card = {
        "playground_package_id": normalize_text(source_playground.get("playground_package_id")) or f"playground-{slugify(f'{concept_id}-{concept_version}', 'playground')}",
        "swarm_run_id": swarm_run_id,
        "concept_id": concept_id,
        "concept_version": concept_version,
        "container_ref": container_ref,
        "review_status": review_status,
        "stage_count": len(stage_executions),
        "stages": [
            {
                "stage_name": normalize_text(stage.get("stage_name")),
                "role_owner": normalize_text(stage.get("role_owner")),
                "status": normalize_text(stage.get("status")),
            }
            for stage in stage_executions
        ],
        "generated_at": generated_at,
    }

    dataset_path = bundle_dir / "synthetic-dataset.json"
    card_path = bundle_dir / "playground-card.json"
    server_path = bundle_dir / "playground_server.py"
    dockerfile_path = bundle_dir / "Dockerfile"
    launch_path = bundle_dir / "launch-instructions.md"
    readme_path = bundle_dir / "README.md"

    write_json(synthetic_dataset, dataset_path)
    write_json(playground_card, card_path)
    write_text(server_path, build_server_source())
    write_text(dockerfile_path, build_dockerfile())

    archive_name = f"{slugify(f'{concept_id}-{concept_version}', 'playground')}-bundle.tar.gz"
    launch_text = build_launch_instructions(container_ref, archive_name)
    readme_text = textwrap.dedent(
        f"""
        # Playground Bundle

        - `Concept ID`: `{concept_id}`
        - `Concept Version`: `{concept_version}`
        - `Swarm Run`: `{swarm_run_id}`
        - `Container Ref`: `{container_ref}`
        - `Data Profile`: `synthetic`
        - `Evidence Bundle`: `{evidence_bundle_ref}`
        """
    ).strip()
    write_text(launch_path, launch_text)
    write_text(readme_path, readme_text)

    archive_path = output_dir / archive_name

    playground_package = {
        "playground_package_id": playground_card["playground_package_id"],
        "swarm_run_id": swarm_run_id,
        "concept_id": concept_id,
        "concept_version": concept_version,
        "container_ref": container_ref,
        "launch_instructions_ref": str(launch_path),
        "data_profile": "synthetic",
        "evidence_bundle_ref": evidence_bundle_ref,
        "review_status": review_status,
        "bundle_root": str(bundle_dir),
        "bundle_archive_ref": str(archive_path),
        "generated_at": generated_at,
    }

    manifest_path = bundle_dir / "playground-package.json"
    write_json(playground_package, manifest_path)

    with tarfile.open(archive_path, "w:gz") as archive:
        archive.add(bundle_dir, arcname="playground-bundle")

    response = {
        "status": "packaged",
        "playground_package": playground_package,
        "files": {
            "dockerfile_ref": str(dockerfile_path),
            "server_ref": str(server_path),
            "dataset_ref": str(dataset_path),
            "card_ref": str(card_path),
            "launch_instructions_ref": str(launch_path),
            "readme_ref": str(readme_path),
            "manifest_ref": str(manifest_path),
            "archive_ref": str(archive_path),
        },
    }
    write_json(response, args.output)
    return 0


def main() -> int:
    args = parse_args()
    if args.command == "package":
        return package_playground(args)
    raise ValueError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
