"""Run the existing suite and deterministic waveform lab without shared libraries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["all", "original", "green", "negative"], default="all")
    parser.add_argument("--out", type=Path, default=ROOT / "build/divider_lab/sim")
    args = parser.parse_args()
    vsim = shutil.which("vsim")
    if not vsim:
        raise SystemExit("vsim is not on PATH")
    modes = ["original", "green", "negative"] if args.mode == "all" else [args.mode]
    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    for mode in modes:
        # Reuse only our named output directory; do not delete libraries or data.
        directory = args.out.resolve() / mode
        directory.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, DIVIDER_LAB_ROOT=ROOT.as_posix(), DIVIDER_LAB_MODE=mode)
        command = [vsim, "-c", "-l", "transcript.log", "-wlf", "divider.wlf",
                   "-do", f'do "{(ROOT / "tools/divider_lab/run_sim.do").as_posix()}"']
        proc = subprocess.run(command, cwd=directory, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, errors="replace", timeout=180)
        (directory / "console.log").write_text(proc.stdout, encoding="utf-8")
        pass_marker = ("[DIVIDER-TB] RESULT: PASS cases=42" if mode == "original"
                       else "[DIVIDER-LAB] RESULT: PASS completed=5 cancelled=1")
        marker_seen = pass_marker in proc.stdout
        assertion_failure = "LAB_RESULT_MISMATCH case=1 expected_q=0000000d actual_q=0000000e" in proc.stdout
        errors_seen = any(marker in proc.stdout for marker in ("** Error:", "** Fatal:", "** Failure:"))
        passed = proc.returncode == 0 and marker_seen and not errors_seen
        trace_valid = None
        if mode == "green":
            try:
                rows = [json.loads(line) for line in (directory / "trace.jsonl").read_text().splitlines()]
                finals = [row for row in rows if row["phase"] == "complete"]
                trace_valid = (len(rows) == 213 and len(finals) == 5
                               and finals[0]["quotient"] == 14 and finals[0]["remainder"] == 2)
            except (OSError, ValueError, KeyError):
                trace_valid = False
            passed = passed and trace_valid
        if mode == "negative":
            # A generic compile/license error MUST NOT count as successful RED evidence.
            passed = assertion_failure and not marker_seen and "** Fatal:" in proc.stdout
        item = {"mode": mode, "process_returncode": proc.returncode,
                "pass_marker_seen": marker_seen, "expected_assertion_seen": assertion_failure,
                "trace_valid": trace_valid, "accepted": passed, "command": command}
        results.append(item)
        print(json.dumps(item, ensure_ascii=False), flush=True)
        for line in proc.stdout.splitlines():
            if "DIVIDER-" in line or "Fatal" in line or "LAB_RESULT_MISMATCH" in line:
                print(line)
    summary = {"seed": 20260909, "rtl_sha256": hashlib.sha256(
        (ROOT / "src/core/radix2_divider.sv").read_bytes()).hexdigest(), "runs": results}
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    # --mode negative exposes the rejected functional check as nonzero.
    # --mode all succeeds if GREEN passes AND the precise intended RED is detected.
    if args.mode == "negative":
        return 1 if results[0]["accepted"] else 2
    return 0 if all(item["accepted"] for item in results) else 1


if __name__ == "__main__":
    sys.exit(main())
