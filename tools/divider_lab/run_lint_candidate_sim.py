"""Functionally regress the generated explicit-width lint candidate."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
candidate = root / "build/divider_lab/lint/width_explicit/radix2_divider.sv"
if not candidate.exists():
    raise SystemExit("Run lint_lab.py in WSL first; generated candidate is missing")
out = root / "build/divider_lab/lint/candidate_sim"
out.mkdir(parents=True, exist_ok=True)
vsim = shutil.which("vsim")
if not vsim:
    raise SystemExit("vsim is not on PATH")
env = dict(os.environ, DIVIDER_LAB_ROOT=root.as_posix())
command = [vsim, "-c", "-l", "transcript.log", "-wlf", "candidate.wlf",
           "-do", f'do "{(root / "tools/divider_lab/run_lint_candidate_sim.do").as_posix()}"']
run = subprocess.run(command, cwd=out, env=env, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, text=True, errors="replace", timeout=180)
(out / "console.log").write_text(run.stdout, encoding="utf-8")
marker = "[DIVIDER-TB] RESULT: PASS cases=42"
ok = run.returncode == 0 and marker in run.stdout and not any(
    item in run.stdout for item in ("** Error:", "** Fatal:", "** Failure:"))
print(f"candidate_42_case_sim: {'PASS' if ok else 'FAIL'} returncode={run.returncode}")
sys.exit(0 if ok else 1)
