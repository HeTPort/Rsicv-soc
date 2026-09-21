#!/usr/bin/env python3
"""Summarize and gate one routed Vivado power-analysis result."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


POWER_VALUE_RE = re.compile(r"\|\s*([^|]+?)\s*\|\s*([<>]?[0-9.]+)\s*\|")
MAPPING_RE = re.compile(r"Design Nets Matched\s*\|\s*([0-9.]+)%\s*\((\d+)/(\d+)\)")
SOURCE_RE = re.compile(r"static probability\s*=.*?\(([ASPCD])\)")


def parse_power_report(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    values: dict[str, Any] = {}
    wanted = {
        "Total On-Chip Power (W)": "total_w",
        "Dynamic (W)": "dynamic_w",
        "Device Static (W)": "static_w",
    }
    for label, raw_value in POWER_VALUE_RE.findall(text):
        key = wanted.get(label.strip())
        if key and key not in values:
            values[key] = float(raw_value.lstrip("<>"))
    confidence = re.search(r"\|\s*Confidence Level\s*\|\s*([^|]+?)\s*\|", text)
    if confidence:
        values["confidence"] = confidence.group(1).strip()
    mapping = MAPPING_RE.search(text)
    if mapping:
        values["mapping_percent_displayed"] = float(mapping.group(1))
        values["mapped_nets"] = int(mapping.group(2))
        values["design_nets"] = int(mapping.group(3))
        values["mapping_percent_exact"] = (
            100.0 * values["mapped_nets"] / values["design_nets"]
        )
    return values


def parse_metadata(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def parse_switching_sources(path: Path) -> dict[str, int]:
    counts = Counter(SOURCE_RE.findall(path.read_text(encoding="utf-8", errors="replace")))
    return {
        "explicit_bridge_a": counts["A"],
        "simulation_direct_s": counts["S"],
        "probabilistic_p": counts["P"],
        "clock_derived_c": counts["C"],
        "default_d": counts["D"],
    }


def reviewed_alternative_passes(path: Path | None) -> tuple[bool, str | None]:
    if path is None:
        return False, None
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("status") != "PASS":
        return False, "alternative overall status is not PASS"
    if data.get("reviewed") is not True:
        return False, "alternative is not marked reviewed"
    blocks = data.get("required_blocks")
    if not isinstance(blocks, list) or not blocks:
        return False, "alternative has no required_blocks"
    failed = [
        block.get("name", "<unnamed>")
        for block in blocks
        if not isinstance(block, dict) or block.get("status") != "PASS"
    ]
    if failed:
        return False, f"alternative block failures: {', '.join(failed)}"
    return True, None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--min-mapping-percent", type=float, default=80.0)
    parser.add_argument("--reviewed-alternative", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--vivado-subdir", default="vivado")
    args = parser.parse_args()

    vivado_dir = args.run_dir / args.vivado_subdir
    activity_report = vivado_dir / "power_activity.rpt"
    if not activity_report.is_file():
        activity_report = vivado_dir / "power_saif.rpt"
    paths = {
        "vectorless": vivado_dir / "power_vectorless.rpt",
        "activity": activity_report,
        "switching": vivado_dir / "switching_activity.rpt",
        "metadata": vivado_dir / "vivado_power_metadata.txt",
    }
    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        print("POWER_RUN_GATE: FAIL", file=sys.stderr)
        for path in missing:
            print(f"ERROR: missing required report: {path}", file=sys.stderr)
        return 1

    try:
        vectorless = parse_power_report(paths["vectorless"])
        activity = parse_power_report(paths["activity"])
        metadata = parse_metadata(paths["metadata"])
        sources = parse_switching_sources(paths["switching"])
        alternative_ok, alternative_error = reviewed_alternative_passes(
            args.reviewed_alternative
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"POWER_RUN_GATE: FAIL ({exc})", file=sys.stderr)
        return 1

    required_power = ("total_w", "dynamic_w", "static_w")
    errors = [
        f"{name} report lacks {field}"
        for name, report in (("vectorless", vectorless), ("activity", activity))
        for field in required_power
        if field not in report
    ]
    mapping = activity.get("mapping_percent_exact")
    mapping_ok = isinstance(mapping, float) and mapping >= args.min_mapping_percent
    if not mapping_ok and not alternative_ok:
        detail = "missing" if mapping is None else f"{mapping:.3f}%"
        errors.append(
            f"SAIF mapping {detail} is below {args.min_mapping_percent:.1f}% and "
            "no reviewed block-level alternative passed"
        )
    if alternative_error:
        errors.append(alternative_error)

    try:
        routed_wns = float(metadata["ROUTED_WNS_NS"])
        if routed_wns < 0.0:
            errors.append(f"routed WNS is negative: {routed_wns} ns")
    except (KeyError, ValueError):
        errors.append("metadata lacks a numeric ROUTED_WNS_NS")

    summary = {
        "schema_version": 1,
        "status": "PASS" if not errors else "FAIL",
        "run_dir": str(args.run_dir.resolve()),
        "mapping_gate": {
            "minimum_percent": args.min_mapping_percent,
            "overall_pass": mapping_ok,
            "reviewed_alternative": str(args.reviewed_alternative.resolve())
            if args.reviewed_alternative
            else None,
            "reviewed_alternative_pass": alternative_ok,
        },
        "vectorless": vectorless,
        "activity": activity,
        "switching_sources": sources,
        "metadata": metadata,
        "errors": errors,
    }
    output = args.output or vivado_dir / "power_run_summary.json"
    output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    print(f"POWER_RUN_GATE: {summary['status']}")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
