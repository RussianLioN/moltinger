#!/usr/bin/env python3

import datetime as dt
import hashlib
import json
import pathlib
import sys

monitor_path = pathlib.Path(sys.argv[1])
state_path = pathlib.Path(sys.argv[2])
threshold = sys.argv[3]
issue_action_mode = sys.argv[4]
warnings = json.loads(sys.argv[5])

ALLOWED_RECOMMENDATIONS = {"upgrade-now", "upgrade-later", "ignore", "investigate"}
ALLOWED_VERSION_STATUS = {"ahead", "current", "behind", "unknown"}
PRIORITY_RANK = {"low": 1, "medium": 2, "high": 3}


def load_monitor_report(path: pathlib.Path):
    notes = []
    evidence = []
    data = {}
    if not path.is_file():
        notes.append(f"Monitor report not found: {path}")
        evidence.append("Advisor could not load the underlying monitor report.")
        return data, notes, evidence
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Failed to parse monitor report JSON: {exc}")
        evidence.append("Advisor could not parse the underlying monitor report.")
        return {}, notes, evidence
    return data, notes, evidence


def normalize_change(item, index):
    if not isinstance(item, dict):
        return None
    change_id = str(item.get("id", f"change:{index}")).strip() or f"change:{index}"
    summary = str(item.get("summary", "")).strip()
    reason = str(item.get("reason", "")).strip()
    relevance = str(item.get("relevance", "none")).strip()
    if not summary or not reason or relevance not in {"high", "medium", "low", "none"}:
        return None
    return {
        "id": change_id,
        "summary": summary,
        "relevance": relevance,
        "reason": reason,
    }


def normalize_monitor_snapshot(raw, notes, evidence):
    if not isinstance(raw, dict):
        raw = {}

    local_version = str(raw.get("local_version", "unknown")).strip() or "unknown"
    latest_version = str(raw.get("latest_version", "unknown")).strip() or "unknown"
    version_status = str(raw.get("version_status", "unknown")).strip()
    if version_status not in ALLOWED_VERSION_STATUS:
        notes.append(f"Monitor report had invalid version_status '{version_status}', normalized to unknown.")
        version_status = "unknown"

    recommendation = str(raw.get("recommendation", "investigate")).strip()
    if recommendation not in ALLOWED_RECOMMENDATIONS:
        notes.append(f"Monitor report had invalid recommendation '{recommendation}', normalized to investigate.")
        recommendation = "investigate"

    repo_traits = []
    for item in raw.get("repo_workflow_traits", []):
        value = str(item).strip()
        if value and value not in repo_traits:
            repo_traits.append(value)

    relevant_changes = []
    for index, item in enumerate(raw.get("relevant_changes", []), start=1):
        normalized = normalize_change(item, index)
        if normalized is not None:
            relevant_changes.append(normalized)

    monitor_evidence = []
    for item in raw.get("evidence", []):
        value = str(item).strip()
        if value and value not in monitor_evidence:
            monitor_evidence.append(value)

    required = ["local_version", "latest_version", "version_status", "recommendation", "repo_workflow_traits", "relevant_changes", "evidence"]
    missing = [field for field in required if field not in raw]
    if missing:
        notes.append("Monitor report was missing required fields: " + ", ".join(missing))
        recommendation = "investigate"
        if not monitor_evidence:
            monitor_evidence.append("Advisor fell back to investigate because the underlying monitor contract was incomplete.")

    if not monitor_evidence:
        monitor_evidence.extend(evidence or ["Advisor did not receive explicit evidence from the monitor report."])

    return {
        "local_version": local_version,
        "latest_version": latest_version,
        "version_status": version_status,
        "recommendation": recommendation,
        "repo_workflow_traits": repo_traits,
        "relevant_changes": relevant_changes,
        "evidence": monitor_evidence,
    }


def load_state(path: pathlib.Path):
    notes = []
    if not path.is_file():
        notes.append("Advisor state file not found; treating this as a fresh evaluation.")
        return {}, notes
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Advisor state file could not be parsed and was ignored: {exc}")
        return {}, notes
    if not isinstance(data, dict):
        notes.append("Advisor state file was not an object and was ignored.")
        return {}, notes
    return data, notes


def meets_threshold(recommendation: str, configured: str) -> bool:
    if configured == "ignore":
        return True
    if configured == "upgrade-later":
        return recommendation in {"upgrade-later", "upgrade-now"}
    if configured == "upgrade-now":
        return recommendation == "upgrade-now"
    if configured == "investigate":
        return recommendation == "investigate"
    return False


RULES = [
    {
        "id": "worktree-guidance",
        "title": "Review worktree guidance and topology helpers",
        "priority": "high",
        "category": "workflow",
        "keywords": ["worktree", "workspace"],
        "traits": ["worktree-discipline"],
        "rationale": "Upstream Codex behavior changed in an area this repository uses heavily for dedicated worktree lanes.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            "docs/GIT-TOPOLOGY-REGISTRY.md",
        ],
        "next_steps": [
            "Review worktree instructions and examples against the latest Codex behavior.",
            "Validate any worktree helper flows that assume older Codex semantics.",
        ],
    },
    {
        "id": "approval-profile-review",
        "title": "Audit approval and sandbox guidance",
        "priority": "high",
        "category": "workflow",
        "keywords": ["approval", "permission profile", "sandbox"],
        "traits": ["approval-boundaries"],
        "rationale": "This repository encodes explicit approval and sandbox expectations, so Codex changes in that area can change operator behavior.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            "scripts/codex-profile-launch.sh",
        ],
        "next_steps": [
            "Re-read approval policy guidance and compare it with the new Codex release behavior.",
            "Update local launch defaults or docs if the approval surface changed.",
        ],
    },
    {
        "id": "agent-delegation-review",
        "title": "Review multi-agent and resume workflow guidance",
        "priority": "high",
        "category": "workflow",
        "keywords": ["multi-agent", "multi agent", "resume"],
        "traits": ["agents-surface"],
        "rationale": "The repository relies on agent delegation patterns, so Codex changes around delegation or resume can require workflow updates.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            ".claude/commands/",
        ],
        "next_steps": [
            "Review delegation guidance and any long-running session instructions.",
            "Check whether resumed sessions still match the current repo expectations.",
        ],
    },
    {
        "id": "js-repl-guidance",
        "title": "Refresh js_repl usage guidance",
        "priority": "high",
        "category": "tooling",
        "keywords": ["js_repl", "js repl", "repl"],
        "traits": ["js-repl-surface"],
        "rationale": "The repo uses js_repl as a first-class tool, so Codex changes there can require examples or guardrail updates.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
        ],
        "next_steps": [
            "Check whether js_repl examples and caveats still reflect current Codex behavior.",
            "Update wrapper guidance if js_repl capabilities or constraints changed.",
        ],
    },
    {
        "id": "skills-surface-review",
        "title": "Review skill bridge and MCP guidance",
        "priority": "medium",
        "category": "tooling",
        "keywords": ["skill", "mcp", "plugin"],
        "traits": ["skills-surface", "agents-md-boundaries"],
        "rationale": "Changes to skills, plugins, or MCP behavior can affect how this repo documents or bridges Codex capabilities.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            ".claude/skills/",
        ],
        "next_steps": [
            "Check whether skill or MCP guidance needs refresh after the Codex update.",
            "Verify any repo-specific bridge expectations still hold.",
        ],
    },
    {
        "id": "runbook-refresh",
        "title": "Refresh Codex runbooks and examples",
        "priority": "medium",
        "category": "docs",
        "keywords": ["agents.md", "project docs", "doc refresh", "prompt"],
        "traits": ["agents-md-boundaries"],
        "rationale": "Codex workflow changes often land first as instruction or runbook drift in this repository.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            "docs/codex-cli-update-monitor.md",
        ],
        "next_steps": [
            "Compare the current runbooks with the updated Codex behavior.",
            "Refresh examples where operator steps have changed.",
        ],
    },
]


def build_suggestions(snapshot):
    suggestion_map = {}
    combined_texts = []
    for change in snapshot["relevant_changes"]:
        combined_texts.append(" ".join([change["summary"], change["reason"]]).lower())
    combined_text = "\n".join(combined_texts)
    trait_set = set(snapshot["repo_workflow_traits"])

    for rule in RULES:
        if rule["traits"] and not trait_set.intersection(rule["traits"]):
            continue
        if not any(keyword in combined_text for keyword in rule["keywords"]):
            continue
        suggestion_map[rule["id"]] = {
            "id": rule["id"],
            "title": rule["title"],
            "priority": rule["priority"],
            "category": rule["category"],
            "rationale": rule["rationale"],
            "impacted_paths": rule["impacted_paths"],
            "next_steps": rule["next_steps"],
        }

    if snapshot["recommendation"] == "investigate" and "investigate-gap" not in suggestion_map:
        suggestion_map["investigate-gap"] = {
            "id": "investigate-gap",
            "title": "Investigate the underlying monitor gap before changing repo workflows",
            "priority": "high",
            "category": "investigation",
            "rationale": "The advisor cannot safely recommend concrete repository changes until the underlying monitor evidence is reliable again.",
            "impacted_paths": [
                "scripts/codex-cli-update-monitor.sh",
                "docs/codex-cli-update-monitor.md",
                "docs/research/",
            ],
            "next_steps": [
                "Inspect why the monitor returned investigate or incomplete evidence.",
                "Regenerate a trustworthy monitor report before making repository workflow changes.",
            ],
        }

    if not suggestion_map and snapshot["relevant_changes"]:
        suggestion_map["codex-runtime-review"] = {
            "id": "codex-runtime-review",
            "title": "Review Codex runtime guidance for this repository",
            "priority": "medium",
            "category": "workflow",
            "rationale": "Relevant Codex changes were detected, but they did not map cleanly to a narrower heuristic bucket.",
            "impacted_paths": [
                "AGENTS.md",
                "docs/CODEX-OPERATING-MODEL.md",
            ],
            "next_steps": [
                "Review the relevant monitor evidence and decide which operator guidance needs refresh.",
            ],
        }

    suggestions = list(suggestion_map.values())
    suggestions.sort(key=lambda item: (-PRIORITY_RANK[item["priority"]], item["title"]))
    return suggestions


def build_fingerprint(snapshot, suggestions):
    payload = {
        "latest_version": snapshot["latest_version"],
        "local_version": snapshot["local_version"],
        "version_status": snapshot["version_status"],
        "recommendation": snapshot["recommendation"],
        "relevant_change_ids": [item["id"] for item in snapshot["relevant_changes"]],
        "suggestion_ids": [item["id"] for item in suggestions],
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode()).hexdigest()


def build_notification(snapshot, state, threshold_value, fingerprint, notes):
    recommendation = snapshot["recommendation"]
    previous = str(state.get("last_fingerprint", "")).strip()

    if recommendation == "investigate":
        if previous and previous == fingerprint:
            return {
                "status": "suppressed",
                "changed": False,
                "threshold": threshold_value,
                "fingerprint": fingerprint,
                "reason": "The same investigate state was already seen earlier, so the advisor suppressed a duplicate alert.",
                "notes": notes + ["Underlying monitor still requires investigation."],
            }
        return {
            "status": "investigate",
            "changed": True,
            "threshold": threshold_value,
            "fingerprint": fingerprint,
            "reason": "The underlying monitor requires investigation, so the advisor cannot stay silent.",
            "notes": notes,
        }

    if not meets_threshold(recommendation, threshold_value):
        return {
            "status": "none",
            "changed": False,
            "threshold": threshold_value,
            "fingerprint": fingerprint,
            "reason": f"Recommendation '{recommendation}' is below notification threshold '{threshold_value}'.",
            "notes": notes,
        }

    if previous and previous == fingerprint:
        return {
            "status": "suppressed",
            "changed": False,
            "threshold": threshold_value,
            "fingerprint": fingerprint,
            "reason": "This actionable Codex update state matches the last one the advisor already surfaced.",
            "notes": notes,
        }

    return {
        "status": "notify",
        "changed": True,
        "threshold": threshold_value,
        "fingerprint": fingerprint,
        "reason": "A new actionable Codex update state was detected for this repository.",
        "notes": notes,
    }


def build_implementation_brief(snapshot, notification, suggestions):
    impacted_paths = []
    for suggestion in suggestions:
        for path in suggestion["impacted_paths"]:
            if path not in impacted_paths:
                impacted_paths.append(path)

    top_priorities = [suggestion["title"] for suggestion in suggestions[:3]]
    if not top_priorities:
        if snapshot["recommendation"] == "ignore":
            top_priorities = ["No repository follow-up is needed right now."]
        else:
            top_priorities = ["Review the advisor evidence before changing repository workflows."]

    summary = (
        f"Codex CLI {snapshot['local_version']} -> {snapshot['latest_version']} "
        f"is currently '{snapshot['recommendation']}' for this repository, and the advisor marked the run as '{notification['status']}'."
    )

    notes = [
        f"Notification threshold: {notification['threshold']}",
        f"Relevant change count: {len(snapshot['relevant_changes'])}",
    ]
    if not suggestions:
        notes.append("No concrete repository change suggestion was generated from the current evidence.")

    return {
        "summary": summary,
        "top_priorities": top_priorities,
        "impacted_paths": impacted_paths,
        "notes": notes,
    }


raw_monitor, load_notes, load_evidence = load_monitor_report(monitor_path)
state_data, state_notes = load_state(state_path)
base_notes = list(load_notes) + list(state_notes)
for warning in warnings:
    if warning:
        base_notes.append(f"Advisor warning: {warning}")

monitor_snapshot = normalize_monitor_snapshot(raw_monitor, base_notes, load_evidence)
suggestions = build_suggestions(monitor_snapshot)
fingerprint = build_fingerprint(monitor_snapshot, suggestions)
notification = build_notification(monitor_snapshot, state_data, threshold, fingerprint, base_notes)
implementation_brief = build_implementation_brief(monitor_snapshot, notification, suggestions)

if issue_action_mode == "upsert":
    issue_action = {
        "mode": "skipped",
        "requested": True,
        "notes": ["Explicit issue sync was requested; final issue action will be applied after advisor evaluation."],
    }
else:
    issue_action = {
        "mode": "suggested" if notification["status"] in {"notify", "investigate"} else "none",
        "requested": False,
        "notes": ["Tracker sync was not requested during initial advisor evaluation."],
    }

report = {
    "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    "monitor_snapshot": monitor_snapshot,
    "notification": notification,
    "project_change_suggestions": suggestions,
    "implementation_brief": implementation_brief,
    "issue_action": issue_action,
}
print(json.dumps(report, indent=2))
