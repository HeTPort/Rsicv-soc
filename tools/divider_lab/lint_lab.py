#!/usr/bin/env python3
"""Reproduce real Verilator RED/GREEN lint evidence without editing SoC RTL.

Windows/WSL command from the repository root:
  wsl -d Ubuntu --exec python3 /mnt/d/Rsicv-soc-worktrees/phase2-act4-cleanup/tools/divider_lab/lint_lab.py

The only generated RTL is a mechanical one-line teaching copy under build/.
This driver checks actual warning IDs and exit codes, not just log existence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    executable = shutil.which(args.verilator)
    if executable is None:
        print("NOT RUN: Verilator was not found; no software was installed.", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parents[2]
    out = root / "build/divider_lab/lint"
    copy_dir = out / "width_explicit"
    copy_dir.mkdir(parents=True, exist_ok=True)
    original = root / "src/core/radix2_divider.sv"
    original_hash = sha256(original)
    original_text = original.read_text(encoding="utf-8")
    old = "if (iteration_q == DW-1) begin"
    new = "if (iteration_q == COUNT_W'(DW-1)) begin"
    if original_text.count(old) != 1:
        raise RuntimeError("Expected exactly one original comparison; review the experiment after RTL changes.")
    width_copy = copy_dir / "radix2_divider.sv"
    width_copy.write_text(original_text.replace(old, new), encoding="utf-8")
    version = subprocess.run([executable, "--version"], check=True, text=True, capture_output=True).stdout.strip()
    fixtures = root / "tools/divider_lab/lint_fixtures"
    waiver = fixtures / "divider_reviewed.vlt"
    cases = [
        ("01_original_red", "radix2_divider", [original], [], {"WIDTHEXPAND", "UNUSEDSIGNAL"}),
        ("02_width_explicit_still_red", "radix2_divider", [width_copy], [], {"UNUSEDSIGNAL"}),
        ("03_width_and_review_green", "radix2_divider", [waiver, width_copy], [], set()),
        ("04_latch_bad_red", "latch_bad", [fixtures / "latch_bad.sv"], [], {"LATCH"}),
        ("05_latch_good_green", "latch_good", [fixtures / "latch_good.sv"], [], set()),
    ]
    # Elaboration/lint only, NOT functional verification of these parameter values.
    for width in (2, 8, 64):
        cases.append((f"06_dw{width}_elaboration_green", "radix2_divider", [waiver, width_copy], [f"-GDW={width}"], set()))

    results = []
    for name, top, files, overrides, expected in cases:
        command = [executable, "--lint-only", "--sv", "--Wall", "-DSYNTHESIS", "--top-module", top, *overrides, *map(str, files)]
        completed = subprocess.run(command, cwd=out, text=True, capture_output=True, check=False)
        output = completed.stdout + completed.stderr
        (out / f"{name}.log").write_text(output, encoding="utf-8")
        warning_ids = sorted(set(re.findall(r"%Warning-([A-Z0-9_]+):", output)))
        passed = (set(warning_ids) == expected and ((completed.returncode != 0) if expected else (completed.returncode == 0)))
        # A RED run must fail only because warnings were made fatal, not a crash,
        # syntax error, unavailable include, or an unrelated unsupported feature.
        if expected:
            errors = [line for line in output.splitlines() if line.startswith("%Error")]
            passed = passed and completed.returncode == 1 and len(errors) == 1 and errors[0].startswith("%Error: Exiting due to ")
        result = {
            "case": name,
            "command": command,
            "expected_warning_ids": sorted(expected),
            "actual_warning_ids": warning_ids,
            "exit_code": completed.returncode,
            "experiment_pass": passed,
            "log": str(out / f"{name}.log"),
        }
        results.append(result)
        print(f"{name}: exit={completed.returncode}, warnings={warning_ids}, experiment={'PASS' if passed else 'FAIL'}", flush=True)

    unchanged = sha256(original) == original_hash
    summary = {
        "tool_version": version,
        "source": str(original),
        "source_sha256": original_hash,
        "source_unchanged": unchanged,
        "copy_sha256": sha256(width_copy),
        "transformation": {"before": old, "after": new},
        "scope": "Single-module synthesis-view static lint; no simulation, SoC integration, STA, CDC/RDC, or equivalence claim.",
        "cases": results,
        "experiment_pass": unchanged and all(result["experiment_pass"] for result in results),
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(version)
    print(f"Production RTL unchanged: {unchanged}")
    print(f"Summary: {out / 'summary.json'}")
    return 0 if summary["experiment_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
