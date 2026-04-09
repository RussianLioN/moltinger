#!/usr/bin/env python3
"""Render the tracked shared topology registry markdown."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render git topology registry markdown")
    parser.add_argument("--output", required=True)
    parser.add_argument("--remote-branches", required=True)
    parser.add_argument("--orphan-records", required=True)
    parser.add_argument("--publish-branch", required=True)
    parser.add_argument("--orphan-count", required=True, type=int)
    return parser.parse_args()


def read_tsv(path: Path) -> list[list[str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    return [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()]


def escape_md_cell(value: str) -> str:
    return value.replace("|", "\\|")


def main() -> int:
    args = parse_args()
    output_path = Path(args.output)
    remote_rows = read_tsv(Path(args.remote_branches))
    orphan_rows = read_tsv(Path(args.orphan_records))

    lines: list[str] = [
        "# Git Topology Registry",
        "",
        "**Status**: Generated artifact from shared remote-governance topology and reviewed intent sidecar",
        "**Scope**: Shared remote governance snapshot",
        "**Purpose**: Single reference for unmerged remote branches and reviewed topology intent that still require merge or cleanup decisions.",
        f"**Publish**: Dispatch `scripts/git-topology-registry.sh publish`; the workflow updates dedicated branch `{args.publish_branch}` and opens or updates a PR to `main`",
        "**Local Note**: Local worktrees and local-only branches remain live-only via `scripts/git-topology-registry.sh status` and `check`",
        "**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.",
        "",
        "## Remote Branches Not Merged Into `origin/main`",
        "",
        "| Remote Branch | Current Intent |",
        "|---|---|",
    ]

    for row in remote_rows:
        remote_ref = row[0] if len(row) > 0 else ""
        note = row[2] if len(row) > 2 else ""
        lines.append(f"| `{escape_md_cell(remote_ref)}` | {escape_md_cell(note)} |")

    if args.orphan_count > 0:
        lines.extend(
            [
                "",
                "## Reviewed Intent Awaiting Reconciliation",
                "",
                "| Subject Type | Subject Key | Intent | Note | PR |",
                "|---|---|---|---|---|",
            ]
        )
        for row in orphan_rows:
            orphan_type = row[0] if len(row) > 0 else ""
            orphan_key = row[1] if len(row) > 1 else ""
            orphan_intent = row[2] if len(row) > 2 else ""
            orphan_note = row[3] if len(row) > 3 and row[3] else "Reviewed intent retained until topology or sidecar is reconciled."
            orphan_pr = row[4] if len(row) > 4 and row[4] else "-"
            lines.append(
                "| `{}` | `{}` | `{}` | {} | {} |".format(
                    escape_md_cell(orphan_type),
                    escape_md_cell(orphan_key),
                    escape_md_cell(orphan_intent),
                    escape_md_cell(orphan_note),
                    escape_md_cell(orphan_pr),
                )
            )
        lines.extend(
            [
                "",
                "## Registry Warnings",
                "",
                f"- Reviewed intent contains {args.orphan_count} orphan record(s); keep them until topology catches up or the sidecar is reviewed.",
            ]
        )

    lines.extend(
        [
            "",
            "## Operating Rules",
            "",
            "1. `main` remains the only operational source of truth.",
            "2. This tracked document covers shared remote-governance state only; local worktree and local-only branch topology stay live-only.",
            "3. Before deleting or merging branches, verify this registry and then verify live `git` state again.",
            "4. If remote topology or reviewed intent changes, dispatch the publish flow to refresh this snapshot.",
            "5. Live `git` state wins over this document if they diverge; refresh the registry instead of forcing git to match the doc.",
            "",
            "## Source Commands",
            "",
            "```bash",
            "git for-each-ref --format='%(refname:short)' refs/remotes/origin",
            "cat docs/GIT-TOPOLOGY-INTENT.yaml",
            "```",
            "",
        ]
    )

    output_path.write_text("\n".join(lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
