# Phase 0 Baseline Record

**Accepted:** 2026-07-24

**Baseline commit:** `95ec765`

**Baseline branch:** `codex/architecture-review-roadmap`

**Merge status at acceptance:** not merged into `main`

The owner explicitly accepted commit `95ec765` as the Phase 0 baseline. The
commit exists locally and on
`origin/codex/architecture-review-roadmap`. Keeping it on a review branch does
not weaken the checkpoint: the immutable commit ID identifies the reference
state. Merging it into `main` remains a separate repository decision.

## Working-tree state

The following commands were run from `D:\Rsicv-soc`:

```powershell
git switch codex/architecture-review-roadmap
git status --short
```

Observed result:

```text
Already on 'codex/architecture-review-roadmap'
Your branch is up to date with 'origin/codex/architecture-review-roadmap'.
```

`git status --short` produced no output, confirming a clean working tree.

## Directed RTL regression

Commands:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Tag smoke
```

Result:

| Test | Result |
|---|---|
| `rv32im` | PASS |
| `ebreak` | PASS |
| `ecall` | PASS |
| `illegal_opcode` | PASS |
| `misaligned_lw` | PASS |
| `misaligned_sw` | PASS |
| `misa` | PASS |
| `act4_harness` | PASS |
| `mret` | PASS |

Summary:

```text
All 9 selected tests passed.
```

## Converter/importer unit tests

Command:

```powershell
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Result:

```text
Ran 4 tests in 0.574s

OK
```

## Recorded tools

| Tool | Recorded version/status |
|---|---|
| ModelSim `vlog` | ModelSim SE-64 2019.2 Compiler 2019.04, Apr 17 2019 |
| ModelSim `vsim` | ModelSim SE-64 2019.2 Simulator 2019.04, Apr 17 2019 |
| Python | 3.12.9 |
| WSL | WSL2 |
| WSL distribution | Ubuntu 26.04 LTS |
| RISC-V GNU compiler | `riscv64-unknown-elf-gcc` 14.2.0 |
| Spike | 1.1.1-dev, currently available only in the WSL `root` environment |
| Vivado | Vivado 2019.2 (64-bit), SW Build 2708876, IP Build 2700528 |

Vivado is installed at:

```text
D:\vivado\Vivado\2019.2
```

It is not currently on the ordinary PowerShell `PATH`. The installed tool can
be queried directly with:

```powershell
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' -version
```

For one PowerShell session, the short command can be enabled with:

```powershell
$env:Path = "D:\vivado\Vivado\2019.2\bin;$env:Path"
vivado -version
```

The Spike installation must be made available to the normal WSL user before
the official ACT4 flow is run. ACT4 builds should not be executed as `root`.

## Generated-artifact policy

The repository ignores generated simulation/build output through
`.gitignore`, including:

```text
sim/build/
sim/logs/
sim/work/
sim/transcript
sim/*.vcd
sim/*.wlf
build/
__pycache__/
*.pyc
```

`git ls-files sim/build sim/logs build` returned no tracked paths. Reproducible
scripts, manifests, checked-in test sources, and deliberate test images remain
under source control.

## Baseline conclusion

Phase 0 has a clean, reproducible, owner-accepted reference commit with passing
directed RTL and Python regressions and a recorded tool inventory.

The next engineering gate is Phase 0A in
[`ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md`](ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md):
write a directed test that exposes the killed-CSR side-effect bug, then fix the
RTL while preserving this baseline.
