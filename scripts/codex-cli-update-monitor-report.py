#!/usr/bin/env python3

import datetime as dt
import json
import pathlib
import re
import sys
from html.parser import HTMLParser

local_version = sys.argv[1]
local_features = json.loads(sys.argv[2])
local_notes = json.loads(sys.argv[3])
repo_traits = json.loads(sys.argv[4])
release_source_id = sys.argv[5]
release_source_path = pathlib.Path(sys.argv[6])
max_releases = int(sys.argv[7])
include_issue_signals = sys.argv[8] == "true"
issue_source_id = sys.argv[9]
issue_source_path = pathlib.Path(sys.argv[10])
issue_action_requested = sys.argv[11]
issue_target = sys.argv[12]
warnings = json.loads(sys.argv[13])

RELEVANCE_RANK = {"none": 0, "low": 1, "medium": 2, "high": 3}


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div"}:
            self.parts.append("\n")

    def handle_data(self, data):
        stripped = data.strip()
        if stripped:
            self.parts.append(stripped)

    def text(self) -> str:
        text = "".join(self.parts)
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        return "\n".join(line for line in lines if line)


def normalize_semver(value: str) -> tuple[int, int, int] | None:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", value or "")
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def compare_versions(left: str, right: str) -> int | None:
    left_tuple = normalize_semver(left)
    right_tuple = normalize_semver(right)
    if left_tuple is None or right_tuple is None:
        return None
    if left_tuple < right_tuple:
        return -1
    if left_tuple > right_tuple:
        return 1
    return 0


def parse_release_source(raw: str, limit: int) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []

    if stripped[0] in "[{":
        data = json.loads(stripped)
        if isinstance(data, dict):
            releases = data.get("releases", [])
        elif isinstance(data, list):
            releases = data
        else:
            releases = []
        normalized = []
        for item in releases:
            if not isinstance(item, dict):
                continue
            changes = item.get("changes", [])
            normalized.append(
                {
                    "version": str(item.get("version", "")).strip(),
                    "published_at": str(item.get("published_at", "")).strip(),
                    "changes": [str(change).strip() for change in changes if str(change).strip()],
                }
            )
        return normalized[:limit]

    parser = TextExtractor()
    parser.feed(stripped)
    text = parser.text()
    lines = text.splitlines()

    releases: list[dict] = []
    current = None
    pending_date = ""
    version_pattern = re.compile(r"Codex CLI(?: Release:)?\s*(\d+\.\d+\.\d+)")
    date_pattern = re.compile(r"^\d{4}-\d{2}-\d{2}$")

    for line in lines:
        if date_pattern.match(line):
            pending_date = line
            continue

        match = version_pattern.search(line)
        if match:
            if current:
                releases.append(current)
            current = {
                "version": match.group(1),
                "published_at": pending_date,
                "changes": [],
            }
            pending_date = ""
            continue

        if current is None:
            continue

        if line.lower() in {"new features", "bug fixes", "documentation", "fixes", "improvements"}:
            continue

        if line == "Changelog":
            continue

        if re.search(r"\d+\.\d+\.\d+", line) and "Codex CLI" in line:
            continue

        if line:
            current["changes"].append(line)

    if current:
        releases.append(current)

    cleaned = []
    for item in releases[:limit]:
        deduped = []
        seen = set()
        for change in item["changes"]:
            if change not in seen:
                deduped.append(change)
                seen.add(change)
        cleaned.append(
            {
                "version": item["version"],
                "published_at": item["published_at"],
                "changes": deduped,
            }
        )
    return cleaned


def parse_issue_signals(raw: str) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []
    data = json.loads(stripped)
    if isinstance(data, dict):
        issues = data.get("issues", [])
    elif isinstance(data, list):
        issues = data
    else:
        issues = []
    normalized = []
    for item in issues:
        if not isinstance(item, dict):
            continue
        if item.get("pull_request"):
            continue
        issue_id = item.get("id") or item.get("number")
        if issue_id is None:
            continue
        labels = []
        for label in item.get("labels", []):
            if isinstance(label, dict):
                name = label.get("name")
                if name:
                    labels.append(name)
            elif isinstance(label, str):
                labels.append(label)
        normalized.append(
            {
                "id": str(issue_id),
                "title": str(item.get("title", "")).strip(),
                "state": str(item.get("state", item.get("status", ""))).strip() or "unknown",
                "labels": labels,
                "url": str(item.get("html_url", item.get("url", ""))).strip(),
            }
        )
    return normalized


def relevance_reason(change_text: str, traits: set[str], advisory: bool = False) -> tuple[str, str, list[str]]:
    text = change_text.lower()

    candidates = [
        ("high", "Relevant because this repo relies on dedicated worktrees and topology checks.", ["worktree-discipline"], ["worktree", "/new"]),
        ("high", "Relevant because repo instructions enforce explicit approval and sandbox boundaries.", ["approval-boundaries"], ["approval", "permission profile", "sandbox"]),
        ("high", "Relevant because multi-agent delegation is part of this repo's day-to-day workflow.", ["agents-surface"], ["multi-agent", "multi agent", "resume"]),
        ("high", "Relevant because the repo actively uses js_repl-backed workflows.", ["js-repl-surface"], ["js_repl", "js repl", "repl"]),
        ("medium", "Relevant because the repo uses non-interactive Codex execution patterns.", ["noninteractive-surface"], ["non-interactive", "noninteractive", "codex exec"]),
        ("medium", "Relevant because the repo depends on AGENTS boundaries and instruction refresh flows.", ["agents-md-boundaries"], ["agents.md", "project docs", "doc refresh"]),
        ("low", "Low relevance because the repo currently leans on bridged skills and MCP surfaces more than plugin-first workflows.", ["skills-surface"], ["plugin", "@plugin"]),
        ("medium", "Relevant because the repo actively uses skills, commands, and MCP integrations.", ["skills-surface"], ["skill", "mcp"]),
    ]

    best = ("none", "No strong link to current repo workflow traits was detected.", [])
    for level, reason, required_traits, keywords in candidates:
        if not set(required_traits).intersection(traits):
            continue
        if not any(keyword in text for keyword in keywords):
            continue
        if RELEVANCE_RANK[level] > RELEVANCE_RANK[best[0]]:
            best = (level, reason, required_traits)

    if advisory:
        if best[0] != "none":
            reason = f"{best[1]} Issue signals remain advisory and do not drive the recommendation on their own."
        else:
            reason = "Advisory issue signal captured for operator awareness; no strong repo-specific relevance detected."
        return best[0], reason, list(best[2])

    return best[0], best[1], list(best[2])


release_fetch_ok = release_source_path.is_file()
release_text = release_source_path.read_text() if release_fetch_ok else ""
releases = parse_release_source(release_text, max_releases) if release_fetch_ok else []
latest_version = releases[0]["version"] if releases else "unknown"

compare_result = compare_versions(local_version, latest_version)
if compare_result is None:
    version_status = "unknown"
elif compare_result < 0:
    version_status = "behind"
elif compare_result > 0:
    version_status = "ahead"
else:
    version_status = "current"

traits = set(repo_traits)

candidate_releases = []
if version_status == "behind":
    candidate_releases = [release for release in releases if compare_versions(local_version, release["version"]) == -1]
elif version_status == "unknown" and releases:
    candidate_releases = [releases[0]]

relevant_changes = []
non_relevant_changes = []

for release in candidate_releases:
    for index, change in enumerate(release.get("changes", []), start=1):
        relevance, reason, matched_traits = relevance_reason(change, traits)
        item = {
            "id": f"release:{release['version']}:{index}",
            "summary": change,
            "relevance": relevance,
            "reason": reason,
            "evidence": [f"Release {release['version']} published {release.get('published_at') or 'unknown date'}"]
            + [f"Matched repo trait: {trait}" for trait in matched_traits],
        }
        if relevance in {"high", "medium"}:
            relevant_changes.append(item)
        else:
            non_relevant_changes.append(item)

issue_sources = []
issue_signals = []
if include_issue_signals:
    if issue_source_id:
        issue_sources.append(issue_source_id)
    if issue_source_path.is_file():
        try:
            issue_signals = parse_issue_signals(issue_source_path.read_text())
        except Exception as exc:
            warnings.append(f"Failed to parse issue-signal source: {exc}")
    else:
        warnings.append("Issue-signal intake requested but no issue source was fetched")

for issue in issue_signals:
    relevance, reason, matched_traits = relevance_reason(issue["title"], traits, advisory=True)
    item = {
        "id": f"issue:{issue['id']}",
        "summary": issue["title"],
        "relevance": relevance,
        "reason": reason,
        "evidence": [f"Issue state: {issue['state']}"] + [f"Matched repo trait: {trait}" for trait in matched_traits],
    }
    if relevance in {"high", "medium"}:
        relevant_changes.append(item)
    else:
        non_relevant_changes.append(item)

relevant_changes.sort(key=lambda item: (-RELEVANCE_RANK[item["relevance"]], item["id"]))
non_relevant_changes.sort(key=lambda item: (-RELEVANCE_RANK[item["relevance"]], item["id"]))

evidence = []
if local_version != "missing":
    evidence.append(f"Detected local Codex CLI version {local_version}.")
else:
    evidence.append("Local Codex CLI version could not be detected from PATH.")

if release_fetch_ok and releases:
    evidence.append(f"Compared against latest upstream release {latest_version} from {release_source_id}.")
else:
    evidence.append(f"Primary upstream release source was unavailable: {release_source_id}.")

for note in local_notes:
    evidence.append(note)

if version_status == "behind":
    evidence.append(f"Local Codex CLI is behind the latest checked release by {len(candidate_releases)} scanned release window(s).")
elif version_status == "current":
    evidence.append("Local Codex CLI matches the latest checked release.")
elif version_status == "ahead":
    evidence.append("Local Codex CLI appears newer than the latest checked release source.")
else:
    evidence.append("Version comparison could not be completed confidently.")

if relevant_changes:
    evidence.append(f"Found {len(relevant_changes)} repository-relevant change(s) in the scanned evidence.")
else:
    evidence.append("No newer repository-relevant changes were found in the scanned evidence.")

if include_issue_signals:
    evidence.append(f"Issue-signal intake reviewed {len(issue_signals)} advisory item(s).")

for warning in warnings:
    if warning:
        evidence.append(warning)

high_count = sum(1 for item in relevant_changes if item["relevance"] == "high")
medium_count = sum(1 for item in relevant_changes if item["relevance"] == "medium")

if not release_fetch_ok or latest_version == "unknown":
    recommendation = "investigate"
elif version_status == "ahead":
    recommendation = "investigate"
elif version_status == "unknown":
    recommendation = "investigate"
elif version_status == "current":
    recommendation = "ignore"
elif high_count > 0 or (len(candidate_releases) >= 2 and medium_count > 0):
    recommendation = "upgrade-now"
elif medium_count > 0 or len(candidate_releases) >= 2:
    recommendation = "upgrade-later"
else:
    recommendation = "upgrade-later"

if issue_action_requested == "none":
    issue_action = {
        "mode": "none",
        "requested": False,
        "notes": ["Tracker sync not requested."],
    }
else:
    notes = [
        f"Requested issue action '{issue_action_requested}' was recorded without tracker mutation.",
        "Beads mutation remains deferred until the User Story 3 implementation slice lands.",
    ]
    issue_action = {
        "mode": "skipped",
        "requested": True,
        "notes": notes,
    }
    if issue_target:
        issue_action["target"] = issue_target

report = {
    "checked_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "local_version": local_version,
    "latest_version": latest_version,
    "version_status": version_status,
    "local_features": local_features,
    "repo_workflow_traits": repo_traits,
    "sources": {
        "release_source": release_source_id,
        "issue_signals_included": include_issue_signals,
    },
    "relevant_changes": relevant_changes,
    "non_relevant_changes": non_relevant_changes,
    "recommendation": recommendation,
    "evidence": evidence,
    "issue_action": issue_action,
}

if issue_sources:
    report["sources"]["issue_sources"] = issue_sources

print(json.dumps(report, indent=2))
