# ACT4 RV32I integration handoff

**Status date:** 2026-07-27
**Workspace:** `D:\Rsicv-soc`
**WSL user:** `het`
**Scope:** Official ACT4 4.0.0 RV32I build, import, DUT execution, and failure
classification.

## Session intent and constraints

The task is to build the official ACT4 RV32I tests in WSL, import the resulting
self-checking ELFs into the existing Harvard-memory simulation flow, run them
with ModelSim, and classify failures.

The following constraint remains in force:

- Record and classify failures before changing RTL.
- Do not combine ACT4 integration with AR-002 RTL work.
- Changes under `src/` are out of scope for this task.
- Adapter, build, importer, regression-runner, and testbench changes are
  allowed when they are needed to execute the official corpus.

No RTL source under `src/` has been modified by this work.

## Current state

The task is safely paused. No ACT4 `make` or Sail process is running.

| Stage | State | Evidence |
|---|---:|---|
| Official ACT4 checkout | Complete | Tag `4.0.0`, commit `a7c99303516f4e668f7488f172043392e23b9dfd` |
| WSL toolchain | Complete | Clang/LLVM 21.1.8 and Sail 0.10 available |
| ACT4/UDB dependencies | Complete | UDB 0.1.9 bundle installs successfully |
| RV32I signature ELFs | 39/39 complete | Saved in the WSL-native work directory |
| Sail reference signatures | 39/39 complete | Saved beside the signature ELFs |
| Final self-checking ELFs | 0/39 complete | First final-ELF compile stops on missing DUT macros |
| ELF import | Not started | `build/act4/tests.json` has not been regenerated from the official corpus |
| ModelSim DUT run | Not started | No official ACT4 DUT result exists yet |
| DUT failure classification | Not started | Must follow the first ModelSim baseline |
| Final integration summary | This handoff is the current summary | Update it after the DUT baseline |

Saved incremental work:

```text
/home/het/act4-work/rsicv-soc
```

Current saved counts:

```text
signature_elfs=39
reference_signatures=39
selfcheck_elfs=0
work_directory_size=8.4M
running_processes=0
```

Do not delete `/home/het/act4-work/rsicv-soc`. ACT4 will reuse the 39 completed
signature ELFs and Sail signatures when the build resumes.

## Exact environment

| Component | Version or location |
|---|---|
| ACT4 source | `/home/het/riscv-arch-test` |
| ACT4 version | `4.0.0` |
| ACT4 commit | `a7c99303516f4e668f7488f172043392e23b9dfd` |
| Clang | Ubuntu Clang 21.1.8 |
| LLVM objdump | Ubuntu LLVM 21.1.8 |
| Sail RISC-V | `/home/het/.local/sail-riscv-0.10/bin/sail_riscv_sim`, version 0.10 |
| mise | 2026.7.13 |
| Ruby | 3.4.9 |
| uv | 0.11.6 |
| UDB gem | 0.1.9 |
| ModelSim | `D:\Modelsim2019\win64` |

ACT4 4.0.0 checks for Sail 0.10 exactly. Sail 0.11 is not accepted by this
pinned ACT4 release. The existing RISC-V GCC 14.2.0 is also too old because
ACT4 requires GCC 15 or later, so the supported Clang 21 path is used instead.

The UDB dependency installer originally timed out while downloading four
official release helpers through WSL. The official binaries and checksum files
were downloaded through Windows, their SHA-256 checksums were verified, and
they were placed in the UDB cache:

```text
/home/het/.cache/udb/espresso/espresso-1.0/x64
/home/het/.cache/udb/eqntott/eqntott-392759e/x64
/home/het/.cache/udb/must/must-17fa9f9/x64
/home/het/.cache/udb/z3/z3-4.16.0/x64
```

## Design and implementation approach

The integration keeps three layers separate:

1. ACT4 and Sail run in WSL and generate official self-checking RV32I ELFs.
2. `import_act4.py` converts each ELF into instruction and data `$readmemh`
   images and creates the regression manifest.
3. ModelSim runs the unchanged CPU RTL through `tb_riscv_core`, using the
   manifest to select images, timeout, `tohost`, and simulation RAM depths.

Official ACT4 programs are much larger than the synthesizable SoC's current
16 KiB RAM defaults. The adapter therefore uses a **simulation-only 256 KiB
capacity**:

```text
ACT4 RAM range: 0x0000_0000 through 0x0003_ffff
tohost address: 0x0003_fffc
RAM depth:      65,536 32-bit words
```

This does not decide or alter the final SoC memory map. The normal testbench
defaults remain 4,096 words. ACT4 manifests override the depth only for ACT4
tests.

The converter still initializes both Harvard memories from every loadable ELF
segment. It now emits data only through the highest loaded address, relying on
the RAM modules' existing initialization for the remaining capacity. This
avoids creating 256 KiB of filler twice for every test.

Heavy ACT4 intermediate files belong in WSL-native storage, not `/mnt/d`.
Debug tracing must be disabled for bulk generation. Detailed traces should be
generated only for selected failures after the baseline exists.

## Repository changes currently saved but uncommitted

| File | Purpose |
|---|---|
| `verif/act4/rv32im_core/test_config_clang.yaml` | Select Clang and LLVM objdump for ACT4 |
| `verif/act4/rv32im_core/rvtest_config.h` | Declare zero PMP entries without enabling unsupported features |
| `verif/act4/rv32im_core/rv32im_core.yaml` | Add required zero vendor ID and remove conditionally invalid `HPM_EVENTS` |
| `verif/act4/rv32im_core/sail.json` | Expand the ACT4-only Sail memory region to 256 KiB |
| `verif/act4/rv32im_core/link.ld` | Link official ACT4 programs into the 256 KiB simulation region |
| `verif/act4/rv32im_core/rvmodel_macros.h` | Move `tohost` to `0x0003_fffc`; still needs mandatory no-op interrupt macros |
| `sim/regress/build_act4_wsl.sh` | Support selectable config, tools, target, WSL work directory, RAM size, and `tohost` |
| `sim/regress/elf_to_mem.py` | Trim trailing uninitialized image output |
| `sim/regress/import_act4.py` | Import 256 KiB ACT4 images and emit RAM-depth manifest fields |
| `sim/regress/run_regression.ps1` | Pass optional program/data RAM depths to ModelSim |
| `sim/tb/tb_riscv_core.sv` | Make RAM depths top-level testbench parameters while retaining 4,096-word defaults |
| `sim/regress/test_import_act4.py` | Check ACT4 `tohost` and RAM-depth manifest values |

The following importer tests pass:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Result:

```text
Ran 4 tests
OK
```

## Recorded build failures

The local logs are under `D:\Rsicv-soc\build\act4`. This directory is ignored
by Git, so these logs are local evidence and will not be included in a normal
commit.

| Attempt | Failure classification | Result and handling |
|---:|---|---|
| 1 | Tool-version mismatch | Sail 0.11 was rejected because ACT4 4.0.0 requires Sail 0.10. Installed Sail 0.10 separately. |
| 2 | Compiler-version mismatch | GCC 14.2.0 was rejected because ACT4 requires GCC 15+. Selected supported Clang 21 instead of weakening the version check. |
| 3 | Network/dependency fetch | UDB 0.1.9 timed out downloading Espresso from GitHub. Downloaded all four pinned helpers and checksums through Windows and verified every SHA-256 value. |
| Bundle retry 1 | Invocation error | `bundle install` was run from `framework/`, which has no Gemfile. Recorded, then rerun from `framework/src/act/data`. |
| Bundle retry 2 | Resolved dependency setup | UDB 0.1.9 installed successfully; 47 gems are available. |
| 4 | UDB adapter configuration | Required `VENDOR_ID_BANK/OFFSET` were missing, and `HPM_EVENTS` was invalid when all HPM counters were disabled. Corrected verification metadata only. |
| 5 | Missing DUT adapter header | ACT4 could not find `rvtest_config.h`. Added a minimal zero-PMP header. |
| 6 | Harness capacity | `I-add-00` exceeded the original 16 KiB linker region. Added the manifest-controlled 256 KiB ACT4 simulation capacity. |
| 7 | Debug/storage performance | A debug build on `/mnt/d` produced one incomplete 273,816,376-byte Sail trace. The exact partial trace was removed. |
| 8 | Make variable semantics | Passing `ACT4_DEBUG=False` still enabled debug because ACT4 checks whether `DEBUG` is non-empty. About 2.7 GiB of generated traces were removed; compiled ELFs were retained. |
| 9 | Sail/linker mismatch | Debug was correctly disabled, but Sail still exposed only 16 KiB while the linker used 256 KiB. Reference jobs faulted/spun. The process was stopped and `sail.json` was aligned with the linker. |
| 10 | Incomplete macro contract | All 39 signature ELFs and Sail signatures completed. Final self-checking ELF compilation stopped because mandatory interrupt-related `RVMODEL_*` macros are absent. This is the current resume point. |

None of these attempts is a DUT/RTL functional failure. No official ACT4 ELF
has run on the RTL yet.

## Current blocker

`verif/act4/rv32im_core/rvmodel_macros.h` must satisfy ACT4's mandatory macro
contract. Attempt 10 reports:

```text
RVMODEL_INTERRUPT_LATENCY not defined
RVMODEL_TIMER_INT_SOON_DELAY not defined
RVMODEL_SET_MEXT_INT not defined
RVMODEL_CLR_MEXT_INT not defined
RVMODEL_SET_MSW_INT not defined
RVMODEL_CLR_MSW_INT not defined
```

`tests/env/check_defines.h` also requires the supervisor set/clear macros even
though supervisor mode is not selected:

```text
RVMODEL_SET_SEXT_INT
RVMODEL_CLR_SEXT_INT
RVMODEL_SET_SSW_INT
RVMODEL_CLR_SSW_INT
```

Resume by adding explicit no-op definitions for all set/clear hooks, because
the current testbench has no external, software, or supervisor interrupt
injection mechanism. Use the conventional ACT4 placeholder values:

```c
#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 100
```

The no-op hooks should use the two-argument forms found in official ACT4 target
adapters:

```c
#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)
```

Define the corresponding `MSW`, `SEXT`, and `SSW` forms in the same way. Do
not define `RVMODEL_MTIME_ADDRESS` or advertise an interrupt source. This step
only completes the ACT4 preprocessor interface; it must not imply that
interrupt tests are supported.

## Resume procedure

### 1. Confirm the saved pause state

From Windows PowerShell:

```powershell
wsl.exe -e bash -lc "ps -eo args | grep -E 'make.*riscv-arch-test|sail_riscv_sim' | grep -v grep || true"

wsl.exe -e bash -lc "find /home/het/act4-work/rsicv-soc/rsicv-soc-rv32im-clang/build -type f -name '*.sig.elf' | wc -l; find /home/het/act4-work/rsicv-soc/rsicv-soc-rv32im-clang/build -type f -name '*.sig' | wc -l"
```

Expected counts are `39` and `39`, with no running process.

### 2. Complete the macro contract

Edit only:

```text
D:\Rsicv-soc\verif\act4\rv32im_core\rvmodel_macros.h
```

Add the ten definitions listed in the previous section. Do not modify RTL.

### 3. Resume the incremental ACT4 build

Run from Windows PowerShell. Deliberately omit `ACT4_DEBUG`; do not set it to
the string `False`.

```powershell
wsl.exe -e env `
  PATH=/home/het/.local/bin:/home/het/.local/sail-riscv-0.10/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin `
  ACT4_ROOT=/home/het/riscv-arch-test `
  ACT4_WORK_DIR=/home/het/act4-work/rsicv-soc `
  ACT4_TARGET_NAME=rsicv-soc-rv32im-clang `
  ACT4_EXTENSIONS=I `
  ACT4_JOBS=8 `
  ACT4_CONFIG_FILE=/mnt/d/Rsicv-soc/verif/act4/rv32im_core/test_config_clang.yaml `
  ACT4_COMPILER_TOOL=clang `
  ACT4_OBJDUMP_TOOL=llvm-objdump `
  bash -o pipefail -lc `
  "cd /mnt/d/Rsicv-soc && bash sim/regress/build_act4_wsl.sh 2>&1 | tee build/act4/act4_rv32i_build_resume.log"
```

The build script should:

1. Reuse the existing 39 reference signatures.
2. Produce 39 final self-checking ELFs below
   `/home/het/act4-work/rsicv-soc/rsicv-soc-rv32im-clang/elfs`.
3. Import them into `D:\Rsicv-soc\build\act4\images`.
4. Generate `D:\Rsicv-soc\build\act4\tests.json`.

If the build fails again, preserve its first failure in a new log and classify
it before editing anything else.

### 4. Validate the imported manifest

```powershell
Set-Location D:\Rsicv-soc
python -c "import json; p='build/act4/tests.json'; d=json.load(open(p)); print(len(d['tests'])); print(d['defaults'])"
```

Expected test count: `39`.

Expected defaults include:

```text
tohost_addr=262140
prog_ram_depth=65536
data_ram_depth=65536
```

### 5. Run the first unchanged-RTL baseline

Run all imported ACT4 tests and preserve the console output:

```powershell
Set-Location D:\Rsicv-soc
.\sim\regress\run_regression.ps1 `
  -Manifest .\build\act4\tests.json `
  -Tag act4 2>&1 |
  Tee-Object -FilePath .\build\act4\act4_rv32i_modelsim_baseline.txt
```

Per-test logs will be written below:

```text
D:\Rsicv-soc\sim\logs\regression
```

The runner overwrites a test's log when that test is rerun. Before focused
reruns, copy the first baseline logs to a dated directory under
`build/act4/failure_logs`.

### 6. Classify failures before any RTL work

For each non-pass, record:

- test name;
- result type: compile error, timeout, missing `tohost`, or non-pass `tohost`;
- first failing architectural operation when observable;
- expected behavior from the ACT4 test;
- whether the cause is adapter/configuration, unsupported feature, harness,
  simulator, or DUT behavior;
- paths to the baseline ModelSim log and relevant ELF/objdump;
- whether an RTL change would overlap AR-002.

Use these classification buckets:

| Bucket | Meaning |
|---|---|
| Environment/tool | Missing executable, version mismatch, dependency, or simulator failure |
| Adapter/configuration | UDB, Sail, linker, macro, manifest, converter, or address mismatch |
| Harness/timeout | Testbench completion, memory capacity, timeout, or trace problem |
| Unsupported/not applicable | ACT4 selected behavior not implemented or not advertised by the core |
| DUT/RTL candidate | The unchanged RTL executed an applicable test and produced wrong architectural behavior |

Do not repair a `DUT/RTL candidate` as part of this integration pass. Record it
and coordinate it with the active AR-002 plan first.

### 7. Finish the handoff

Update this document with:

- the final ELF and manifest counts;
- the ModelSim pass/fail totals;
- one row per failing test and its classification;
- the exact baseline log locations;
- recommended follow-up ordering;
- confirmation that no RTL was changed during failure recording.

Then rerun:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Also run the existing non-ACT4 smoke regression to confirm that parameterizing
testbench RAM depth did not change the default test configuration.

## Completion criteria

This integration task is complete when:

- 39 official RV32I self-checking ELFs are built;
- all 39 are imported into the generated manifest;
- all 39 are executed against the unchanged RTL;
- every pass/fail/timeout is recorded;
- every failure is classified before any RTL fix;
- importer unit tests and the existing smoke regression still pass;
- this document contains the final result table and next actions.

Passing all 39 tests is not required to complete the **integration and
classification** milestone. A failing applicable DUT test becomes separate,
prioritized RTL work coordinated with AR-002.
