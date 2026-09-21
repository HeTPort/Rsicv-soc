#!/usr/bin/env python3
"""Enforce a reviewed block-level activity-coverage alternative."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


LINE_RE = re.compile(
    r"^(.*?):\s+static probability = .*?\(([A-Z])\)\s+"
    r"signal rate = ([0-9.eE+-]+)"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("policy", type=Path)
    parser.add_argument("switching_report", type=Path)
    parser.add_argument("functional_log", type=Path)
    parser.add_argument("bridge_json", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--timer-bridge-json", type=Path)
    args = parser.parse_args()

    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    switching_text = args.switching_report.read_text(encoding="utf-8", errors="replace")
    functional_text = args.functional_log.read_text(encoding="utf-8", errors="replace")
    bridge = json.loads(args.bridge_json.read_text(encoding="utf-8"))
    timer_bridge = (
        json.loads(args.timer_bridge_json.read_text(encoding="utf-8"))
        if args.timer_bridge_json else None
    )
    entries = []
    for line in switching_text.splitlines():
        match = LINE_RE.match(line)
        if match:
            entries.append((match.group(1), match.group(2), float(match.group(3))))

    functional_errors = [
        token for token in policy.get("functional_log_required", [])
        if token not in functional_text
    ]
    block_results = []
    for rule in policy["required_blocks"]:
        pattern = re.compile(rule["pattern"])
        sources = set(rule["sources"])
        matches = [item for item in entries if item[1] in sources and pattern.search(item[0])]
        active = [item for item in matches if item[2] > 0.0]
        max_signal_rate_mhz = max((item[2] for item in matches), default=0.0)
        errors = []
        if len(matches) < rule.get("minimum_matches", 0):
            errors.append(
                f"matches {len(matches)} < {rule['minimum_matches']}"
            )
        if len(active) < rule.get("minimum_active", 0):
            errors.append(f"active {len(active)} < {rule['minimum_active']}")
        if "maximum_active" in rule and len(active) > rule["maximum_active"]:
            errors.append(f"active {len(active)} > {rule['maximum_active']}")
        if ("maximum_signal_rate_mhz" in rule and
                max_signal_rate_mhz > rule["maximum_signal_rate_mhz"]):
            errors.append(
                f"max signal rate {max_signal_rate_mhz} MHz > "
                f"{rule['maximum_signal_rate_mhz']} MHz"
            )
        bridge_group = rule.get("bridge_group")
        if bridge_group:
            group = bridge.get("groups", {}).get(bridge_group, {})
            if group.get("total_transitions", 0) <= 0:
                errors.append(f"bridge group {bridge_group} has no transitions")
        timer_bridge_group = rule.get("timer_bridge_group")
        if timer_bridge_group:
            group = (timer_bridge or {}).get("groups", {}).get(timer_bridge_group, {})
            if group.get("total_transitions", 0) <= 0:
                errors.append(
                    f"timer bridge group {timer_bridge_group} has no transitions"
                )
        block_results.append({
            "name": rule["name"],
            "status": "PASS" if not errors else "FAIL",
            "sources": sorted(sources),
            "matched": len(matches),
            "active": len(active),
            "max_signal_rate_mhz": max_signal_rate_mhz,
            "errors": errors,
        })

    errors = []
    if policy.get("reviewed") is not True:
        errors.append("policy is not marked reviewed")
    errors.extend(f"functional log missing: {token}" for token in functional_errors)
    errors.extend(
        f"{block['name']}: {error}"
        for block in block_results
        for error in block["errors"]
    )
    result = {
        "schema_version": 1,
        "reviewed": policy.get("reviewed") is True,
        "status": "PASS" if not errors else "FAIL",
        "policy": str(args.policy.resolve()),
        "switching_report": str(args.switching_report.resolve()),
        "functional_log": str(args.functional_log.resolve()),
        "bridge_json": str(args.bridge_json.resolve()),
        "timer_bridge_json": (
            str(args.timer_bridge_json.resolve()) if args.timer_bridge_json else None
        ),
        "required_blocks": block_results,
        "errors": errors,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    print(f"P0_BLOCK_COVERAGE: {result['status']}")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
