#!/usr/bin/env python3
"""Validate source-controlled power workload manifests and design records."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


POWER_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = POWER_ROOT.parent
WORKLOAD_ROOT = POWER_ROOT / "workloads"
ALLOWED_STATES = {"design", "implemented", "verified", "accepted", "superseded"}
NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
REQUIRED_FIELDS = {
    "schema_version", "name", "version", "state", "purpose",
    "design_document", "source", "target", "measurement",
    "expected_blocks", "oracle", "kpis",
}
REQUIRED_HEADINGS = {
    "## Purpose",
    "## Design intent",
    "## Non-goals",
    "## Fixed inputs and useful work",
    "## Window contract",
    "## Expected block activity",
    "## Functional oracle and failure consequences",
    "## Key performance indicators",
    "## Reproducibility identity",
    "## Risks and limitations",
    "## Verification and evidence",
}


def rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def mapping(value: Any, where: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{where}: expected object")
        return {}
    return value


def nonempty(value: Any, where: str, errors: list[str]) -> str:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{where}: expected nonempty string")
        return ""
    return value


def validate_manifest(path: Path) -> list[str]:
    errors: list[str] = []
    where = rel(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"{where}: cannot parse JSON: {exc}"]
    if not isinstance(data, dict):
        return [f"{where}: root must be an object"]

    missing = sorted(REQUIRED_FIELDS - data.keys())
    if missing:
        errors.append(f"{where}: missing fields: {', '.join(missing)}")

    name = nonempty(data.get("name"), f"{where}.name", errors)
    if name and not NAME_RE.fullmatch(name):
        errors.append(f"{where}.name: must match {NAME_RE.pattern}")
    if name and name != path.parent.name:
        errors.append(f"{where}.name: must match directory '{path.parent.name}'")
    if data.get("schema_version") != 1:
        errors.append(f"{where}.schema_version: expected 1")
    if data.get("state") not in ALLOWED_STATES:
        errors.append(f"{where}.state: invalid lifecycle state")
    nonempty(data.get("version"), f"{where}.version", errors)
    nonempty(data.get("purpose"), f"{where}.purpose", errors)

    design_name = nonempty(
        data.get("design_document"), f"{where}.design_document", errors
    )
    design_path = path.parent / design_name if design_name else None
    if design_path is not None and not design_path.is_file():
        errors.append(f"{where}.design_document: missing '{design_name}'")
    elif design_path is not None:
        text = design_path.read_text(encoding="utf-8")
        for heading in sorted(REQUIRED_HEADINGS):
            if heading not in text:
                errors.append(f"{rel(design_path)}: missing heading '{heading}'")

    source = mapping(data.get("source"), f"{where}.source", errors)
    if source.get("kind") not in {"original", "third_party", "mixed"}:
        errors.append(f"{where}.source.kind: invalid provenance kind")
    source_paths = source.get("paths")
    if not isinstance(source_paths, list) or not source_paths or not all(
        isinstance(item, str) and item for item in source_paths
    ):
        errors.append(f"{where}.source.paths: expected nonempty string list")

    target = mapping(data.get("target"), f"{where}.target", errors)
    for field in (
        "part", "clock_hz", "clock_status", "vivado_top", "simulation_top",
        "dut_instance", "saif_strip_path", "memory_profile",
    ):
        if field not in target:
            errors.append(f"{where}.target: missing '{field}'")
    if not isinstance(target.get("clock_hz"), int) or target.get("clock_hz", 0) <= 0:
        errors.append(f"{where}.target.clock_hz: expected positive integer")

    measurement = mapping(
        data.get("measurement"), f"{where}.measurement", errors
    )
    for field in (
        "window_kind", "warmup_end", "start_marker", "end_marker",
        "work_unit", "work_units", "repeat_runs",
        "dynamic_power_repeatability_percent_max",
    ):
        if field not in measurement:
            errors.append(f"{where}.measurement: missing '{field}'")
    if measurement.get("repeat_runs") != 2:
        errors.append(f"{where}.measurement.repeat_runs: expected 2")
    if measurement.get("dynamic_power_repeatability_percent_max") != 2.0:
        errors.append(
            f"{where}.measurement.dynamic_power_repeatability_percent_max: expected 2.0"
        )

    expected = mapping(
        data.get("expected_blocks"), f"{where}.expected_blocks", errors
    )
    for field in ("active", "idle", "constraint_derived"):
        if not isinstance(expected.get(field), list):
            errors.append(f"{where}.expected_blocks.{field}: expected list")

    oracle = mapping(data.get("oracle"), f"{where}.oracle", errors)
    for field in ("kind", "pass", "failure", "golden_checksum"):
        if field not in oracle:
            errors.append(f"{where}.oracle: missing '{field}'")

    kpis = data.get("kpis")
    if not isinstance(kpis, list) or not kpis:
        errors.append(f"{where}.kpis: expected nonempty list")
    else:
        seen: set[str] = set()
        for index, raw_kpi in enumerate(kpis):
            kpi_where = f"{where}.kpis[{index}]"
            kpi = mapping(raw_kpi, kpi_where, errors)
            for field in ("id", "metric", "unit", "gate", "evidence"):
                nonempty(kpi.get(field), f"{kpi_where}.{field}", errors)
            kpi_id = kpi.get("id")
            if isinstance(kpi_id, str):
                if kpi_id in seen:
                    errors.append(f"{kpi_where}.id: duplicate '{kpi_id}'")
                seen.add(kpi_id)
        if data.get("state") == "design" and any(
            isinstance(kpi, dict) and kpi.get("evidence") != "NOT RUN"
            for kpi in kpis
        ):
            errors.append(f"{where}: design-state KPI evidence must be 'NOT RUN'")

    return errors


def main() -> int:
    manifests = sorted(WORKLOAD_ROOT.glob("*/workload.json"))
    if not manifests:
        print("POWER_WORKLOAD_VALIDATION: FAIL (no manifests found)")
        return 1
    errors = [error for path in manifests for error in validate_manifest(path)]
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(
            f"POWER_WORKLOAD_VALIDATION: FAIL "
            f"({len(errors)} error(s), {len(manifests)} manifest(s))"
        )
        return 1
    print(f"POWER_WORKLOAD_VALIDATION: PASS ({len(manifests)} manifest(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
