# ACT4 architectural-test integration

This directory adapts the RV32IM core to the RISC-V Architectural
Certification Tests (ACT4) version 4.0.0. ACT4 generates self-checking ELF
files with expected results calculated by the Sail reference model. The local
flow converts those ELFs into the two `$readmemh` images required by this
Harvard-memory core and then runs them through the normal ModelSim regression.

The enabled baseline scope is unprivileged RV32I plus RV32M. On 2026-08-03 all
39 RV32I and all 8 RV32M tests passed. Privileged tests remain disabled until
the target configuration and interrupt behavior are ready for that wider scope.

## Data flow

```text
ACT4 source tests + UDB/Sail configuration
                    |
                    v
             self-checking ELF
                    |
                    v
       sim/regress/elf_to_mem.py
             |              |
             v              v
       instruction hex   data hex
             \              /
              \            /
               ACT manifest
                    |
                    v
       run_regression.ps1 + ModelSim
                    |
                    v
     commit store to reserved tohost word
```

## Repository files and ownership

### DUT description

`rv32im_core/rv32im_core.yaml` is the UDB architectural configuration. It
describes what the hardware actually implements, including RV32, I, M, Zicsr,
machine mode, direct-only `mtvec`, trapping misaligned data accesses, and the
current lack of unimplemented-CSR traps.

This file controls test selection. Advertising an unsupported extension causes
invalid failures; omitting a supported extension hides coverage. Treat it as an
executable hardware specification rather than build-system decoration.

### Reference-model description

`rv32im_core/sail.json` configures the Sail reference model to match the DUT:

- XLEN is 32.
- M is enabled; A/F/D/C and other unsupported extensions are disabled.
- ACT4-only simulation RAM occupies `0x0000_0000` through `0x0003_ffff`.
- Misaligned data accesses fault.
- User and supervisor modes are disabled.

The UDB and Sail descriptions must agree. A mismatch can make a correct DUT
look wrong because the reference model computes a different legal result.

### ACT framework configuration

`rv32im_core/test_config.yaml` binds together the compiler, objdump, Sail,
UDB, linker script, and DUT macro directory. `include_priv_tests: false` is a
deliberate coverage boundary, not a claim that machine-mode support is absent.

### Linker and memory map

`rv32im_core/link.ld` places ACT sections into a 256 KiB testbench-only memory
window. This larger capacity lets generated coverage programs run; it does not
change the synthesizable SoC's accepted 64 KiB program region. The script
preserves ACT's required ordering:

```text
.text.init -> .text.rvtest -> .data -> .text.rvmodel -> .bss
```

The linker `ASSERT` rejects an ELF that does not fit instead of allowing the
RTL RAM index to wrap. Address `0x0003_fffc`, the final valid word, is reserved
for `tohost`, so ordinary ACT data must finish below that address.

### DUT-specific assembly macros

`rv32im_core/rvmodel_macros.h` implements ACT termination:

- `RVMODEL_HALT_PASS` stores `1` to `0x0003_fffc`.
- `RVMODEL_HALT_FAIL` stores `2` to `0x0003_fffc`.
- Console and interrupt hooks are empty because those devices do not exist.

The trailing backslash in a C preprocessor macro continues the definition on
the next physical line. The `;` characters separate RISC-V assembly statements
after preprocessing. Numeric label `1:` and branch `1b` form a local loop;
`b` means the nearest earlier label numbered 1.

## One-time WSL setup

ACT4 4.0.0 requires GNU make, Git, its Python/Ruby environment, the RISC-V GNU
toolchain, and Sail. Follow the official ACT4 installation instructions for
`mise` and Sail, then pin the source checkout:

```bash
cd ~
git clone --branch 4.0.0 --depth 1 \
  https://github.com/riscv/riscv-arch-test.git
cd riscv-arch-test
mise trust .mise.toml
```

Confirm the external tools before building:

```bash
make --version
mise --version
riscv64-unknown-elf-gcc --version
riscv64-unknown-elf-objdump --version
sail_riscv_sim --version
```

## Generate and import RV32I or RV32M tests

From Windows PowerShell, the consolidated launcher selects one extension and
handles the Windows-to-WSL repository path:

```powershell
.\sim\regress\run_act4_build.ps1 -Extension I
.\sim\regress\run_act4_build.ps1 -Extension M
```

Use `-Act4Root`, `-Act4WorkDir`, or `-WslRepoPath` only when your WSL layout is
not the default. Run `Get-Help .\sim\regress\run_act4_build.ps1 -Detailed` for
examples.

The equivalent direct WSL flow is:

From the repository mounted in WSL:

```bash
cd /mnt/d/Rsicv-soc
ACT4_ROOT="$HOME/riscv-arch-test" \
ACT4_EXTENSIONS=I \
ACT4_JOBS=1 \
ACT4_DEBUG=True \
bash sim/regress/build_act4_wsl.sh
```

The shell script performs four guarded steps:

1. Check every required external command.
2. Run ACT4 using `verif/act4/rv32im_core/test_config.yaml`.
3. Find final self-checking ELFs under
   `build/act4/work/rsicv-soc-rv32im/elfs`.
4. Convert them and create `build/act4/tests.json`.

`set -euo pipefail` means the script stops on a failed command (`-e`), use of
an unset variable (`-u`), or a failed element of a pipeline (`pipefail`).
`${NAME:-default}` selects an environment value when provided and otherwise
uses the shown default.

## Run imported ACT4 tests on Windows

From PowerShell:

```powershell
Set-Location D:\Rsicv-soc
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# List generated tests.
.\sim\regress\run_regression.ps1 `
  -Manifest .\build\act4\tests.json `
  -List

# Run all imported ACT4 tests.
.\sim\regress\run_regression.ps1 `
  -Manifest .\build\act4\tests.json `
  -Tag act4
```

Alternatively, point the convenience wrapper directly at an ELF directory:

```powershell
.\sim\regress\run_act4.ps1 `
  -ElfDir .\build\act4\work\rsicv-soc-rv32im\elfs
```

Use `-Test <name> -Trace` to debug one failure. Add `-NoCompile` after the RTL
has already been compiled.

## ELF conversion design

`sim/regress/elf_to_mem.py` parses ELF32 headers and `PT_LOAD` program headers
using Python's `struct` module. Format strings begin with `<`, which means
little-endian encoding. For example, `"<IIIIIIII"` reads eight little-endian
32-bit integers from one ELF program header.

For every loadable segment:

- `p_filesz` bytes are copied from the ELF.
- The remainder through `p_memsz` is zero-filled, implementing `.bss`.
- The bytes are copied into both initial Harvard memories.
- Conflicting overlapping segments are rejected.
- Any byte outside `[0x0000, 0x40000)` is rejected.

Both memories initially receive all ELF bytes because software sees one
architectural address space even though this implementation stores instructions
and data in separate physical arrays. After reset, stores update data RAM only;
self-modifying code is therefore intentionally unsupported.

## Debugging sequence

### ACT configuration or generation failure

Read the first error from ACT4. Most early failures mean:

- a UDB parameter does not match its extension set;
- Sail and UDB disagree;
- a required tool is absent from `PATH`; or
- generated sections exceed the linker memory region.

Run only one extension with serialized debug output:

```bash
ACT4_EXTENSIONS=I ACT4_JOBS=1 ACT4_DEBUG=True \
bash sim/regress/build_act4_wsl.sh
```

### Converter reports “outside configured RAM”

Inspect the ELF layout:

```bash
riscv64-unknown-elf-readelf -l failing.elf
riscv64-unknown-elf-objdump -h failing.elf
```

Do not simply increase the converter's RAM size. First decide whether the
physical DUT memory should actually grow; the linker, UDB/Sail memory map,
testbench parameters, and synthesizable RAM depth must tell the same story.

### ModelSim timeout or FAIL

Run the single case with tracing:

```powershell
.\sim\regress\run_regression.ps1 `
  -Manifest .\build\act4\tests.json `
  -Test failing-test-name `
  -NoCompile `
  -Trace
```

Then correlate the final `[COMMIT]` PC and instruction with the ACT-generated
`.objdump`. If the expected result appears wrong, audit UDB/Sail configuration;
if the actual result is wrong, trace the instruction through decode, execute,
LSU, and writeback.

## Coverage expansion order

1. Keep the 39/39 RV32I and 8/8 RV32M baseline continuously green.
2. Enable selected Zicsr and machine-mode tests only after auditing the ACT4
   configuration against the implemented CSR behavior.
3. Add interrupt sources before enabling interrupt-dependent tests.
4. Add Spike differential checking for randomized instruction streams.

ACT4 is architectural checking. It does not replace the existing directed
regression, structural assertions, future bus protocol assertions, or eventual
UVM verification of a larger peripheral subsystem.
