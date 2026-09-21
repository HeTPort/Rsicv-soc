#!/usr/bin/env python3
"""Compare two independently captured, gated power runs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_a", type=Path)
    parser.add_argument("run_b", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--vivado-subdir", default="vivado_reviewed")
    parser.add_argument("--max-percent", type=float, default=2.0)
    args = parser.parse_args()

    manifest_a = load(args.run_a / "run.json")
    manifest_b = load(args.run_b / "run.json")
    summary_a = load(args.run_a / args.vivado_subdir / "power_run_summary.json")
    summary_b = load(args.run_b / args.vivado_subdir / "power_run_summary.json")
    errors = []
    for label, summary in (("run_a", summary_a), ("run_b", summary_b)):
        if summary.get("status") != "PASS":
            errors.append(f"{label} power gate did not pass")
    checkpoint_a = summary_a.get("metadata", {}).get("CHECKPOINT")
    checkpoint_b = summary_b.get("metadata", {}).get("CHECKPOINT")
    if not checkpoint_a or checkpoint_a != checkpoint_b:
        errors.append("routed checkpoint identity mismatch")
    if summary_a.get("metadata", {}).get("ROUTED_WNS_NS") != summary_b.get("metadata", {}).get("ROUTED_WNS_NS"):
        errors.append("routed timing identity mismatch")

    identity_fields = [
        "workload", "workload_version", "clock_hz", "window_cycles",
        "retired_instructions", "work_units", "program_sha256",
        "data_sha256", "report_sha256",
    ]
    mismatches = [
        field for field in identity_fields
        if manifest_a.get(field) != manifest_b.get(field)
    ]
    if mismatches:
        errors.append(f"run identity mismatch: {', '.join(mismatches)}")

    dynamic_a = float(summary_a["activity"]["dynamic_w"])
    dynamic_b = float(summary_b["activity"]["dynamic_w"])
    mean = (dynamic_a + dynamic_b) / 2.0
    percent_difference = 0.0 if mean == 0.0 else 100.0 * abs(dynamic_a - dynamic_b) / mean
    if percent_difference > args.max_percent:
        errors.append(
            f"dynamic-power difference {percent_difference:.6f}% > {args.max_percent:.6f}%"
        )

    result = {
        "schema_version": 1,
        "status": "PASS" if not errors else "FAIL",
        "run_a": str(args.run_a.resolve()),
        "run_b": str(args.run_b.resolve()),
        "identity_fields_checked": identity_fields,
        "dynamic_power_w": {"run_a": dynamic_a, "run_b": dynamic_b},
        "percent_difference": percent_difference,
        "maximum_percent": args.max_percent,
        "errors": errors,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    print(f"P0_POWER_REPEATABILITY: {result['status']}")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
