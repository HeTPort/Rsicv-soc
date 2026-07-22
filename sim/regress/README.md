# Automated regression runner

This directory contains the lightweight regression layer for the RV32IM core.
It deliberately does not require UVM. The runner compiles RTL once, selects
tests from a JSON manifest, launches each test in ModelSim, saves independent
logs, and returns a nonzero process status if any test fails.

## Files

- `tests.json` - test names, firmware images, timeouts, and selection tags.
- `run_regression.ps1` - Windows PowerShell orchestration and result checking.
- `run_regression.cmd` - Command Prompt wrapper that bypasses script policy only
  for this one PowerShell process.
- `build_tests_wsl.sh` - optional GNU-toolchain builder for assembly tests in WSL.
- `elf_to_mem.py` - address-aware RV32 ELF to instruction/data RAM converter.
- `import_act4.py` - converts ACT4 ELF directories and generates a manifest.
- `build_act4_wsl.sh` - generates/imports ACT4 tests in WSL.
- `run_act4.ps1` - convenience wrapper for imported ACT4 ELF directories.

Generated files are kept outside the source directories:

```text
sim/build/regression/work   ModelSim work library
sim/logs/regression         compile and per-test logs
build/tests                 WSL-generated object, ELF, binary, hex, disassembly
```

## Quick start on Windows

From PowerShell:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1
```

From Command Prompt:

```bat
cd /d D:\Rsicv-soc\sim\regress
run_regression.cmd
```

Useful selections:

```powershell
# Show the manifest without compiling or simulating.
./run_regression.ps1 -List

# Run tests having the lsu tag.
./run_regression.ps1 -Tag lsu

# A test matches when it has any requested tag.
./run_regression.ps1 -Tag csr,mret

# Explicit names take priority over tags.
./run_regression.ps1 -Test ebreak,mret

# Reuse the existing compiled library.
./run_regression.ps1 -Tag trap -NoCompile

# Enable commit and pipeline messages in each selected test log.
./run_regression.ps1 -Test ebreak -Trace

# Also request a VCD. Sequential tests overwrite the same VCD in the build
# directory, so use this mainly with one explicitly selected test.
./run_regression.ps1 -Test ebreak -Trace -DumpWaves
```

Success produces process exit code `0`. Manifest, tool, compile, assertion,
timeout, simulator, or architectural failures produce a nonzero exit code.
This makes the same command usable by a person, a batch file, or CI.

## Manifest grammar

`tests.json` uses JSON objects, arrays, strings, and numbers:

```json
{
  "schema_version": 1,
  "defaults": {
    "timeout_cycles": 20000
  },
  "tests": [
    {
      "name": "mret",
      "image": "testdata/m_trap_test.hex",
      "timeout_cycles": 2000,
      "tags": ["all", "smoke", "trap", "csr", "mret"]
    }
  ]
}
```

Important JSON rules:

- `{ ... }` is an object containing named properties.
- `[ ... ]` is an ordered array.
- Property names and strings require double quotes.
- Commas separate properties and array elements, but JSON forbids a trailing
  comma after the final item.
- `image` is relative to the repository root, not the launch directory.
- Optional `data_image` initializes data RAM independently from instruction RAM.
- Optional `tohost_addr` overrides the completion address for that test.
- `timeout_cycles` bounds the test independently of host execution time.
- Tags describe capabilities and allow one test to belong to several suites.

The runner uses **any-tag matching**. `-Tag csr,mret` selects a test when it has
`csr` or `mret`. `-Test` performs exact name selection and takes priority.

## PowerShell grammar used by the runner

### Parameters and types

```powershell
param(
    [string[]]$Tag = @("smoke"),
    [switch]$Trace
)
```

- `[string[]]` declares an array of strings.
- `@(...)` forces an array even when there is only one result.
- `[switch]` is false when absent and true when written on the command line.

### Variables and interpolation

```powershell
$logPath = Join-Path $logDir "$testName.log"
```

Variables begin with `$`. Double-quoted strings expand variables; single-quoted
strings normally do not.

### Pipelines

```powershell
$failed = @($results | Where-Object { $_.Status -ne "PASS" })
```

`|` passes objects rather than plain text. `$_` means the current pipeline
object. `{ ... }` is a script block evaluated for every object.

### Splatting command arguments

```powershell
$vlogArgs = @("-sv", "-work", $workLibrary) + $sourceFiles
$output = & vlog @vlogArgs 2>&1
```

- `&` invokes a command whose name or path is an expression.
- `@vlogArgs` expands an array into separate command-line arguments.
- `2>&1` merges the error stream into captured output.
- `$LASTEXITCODE` contains the native executable's process exit status.

ModelSim can return zero after some simulation failures, depending on how Tcl
exits. The runner therefore requires all three conditions:

```text
[TB] RESULT: PASS is present
no ** Fatal: message is present
the final ModelSim error count is zero
```

### Guaranteed directory restoration

```powershell
Push-Location $buildDir
try {
    # compile and simulate
} finally {
    Pop-Location
}
```

`finally` executes even when an exception is thrown. This prevents a failed
regression from leaving an interactive shell in a surprising directory.

## ModelSim command grammar

The runner ultimately invokes commands equivalent to:

```powershell
vlib D:/Rsicv-soc/sim/build/regression/work
vmap work D:/Rsicv-soc/sim/build/regression/work
vlog -sv -work D:/Rsicv-soc/sim/build/regression/work <absolute-source-files>
vsim -c -voptargs=+acc `
  -gPROGRAM_FILE=D:/Rsicv-soc/testdata/ebreak_test.hex `
  -gTIMEOUT_CYCLES=1000 `
  -gTRACE_ENABLE=0 `
  -gDUMP_WAVES=0 `
  work.tb_riscv_core `
  -do "run -all; quit -f"
```

- `vlib` creates a compiled HDL library.
- `vmap` assigns the logical name `work` to its physical directory.
- `vlog -sv` compiles SystemVerilog.
- `vsim -c` selects console mode.
- `-gNAME=value` overrides a top-level SystemVerilog parameter.
- `-do` supplies Tcl commands; semicolons separate Tcl commands.

The corresponding SystemVerilog parameter declaration is:

```systemverilog
module tb_riscv_core #(
  parameter string PROGRAM_FILE = "../testdata/prog.hex",
  parameter string DATA_FILE = "",
  parameter bit TRACE_ENABLE = 1'b0,
  parameter bit DUMP_WAVES = 1'b0,
  parameter int TIMEOUT_CYCLES = 20000,
  parameter logic [31:0] TOHOST_ADDR = 32'h0000_1000
);
```

Parameters are elaboration-time constants. ModelSim applies `-g` before the
testbench is elaborated, so each test can use a different image and watchdog
without recompiling the RTL.

## Building assembly tests in WSL

From Ubuntu/WSL:

```bash
cd /mnt/d/Rsicv-soc
bash sim/regress/build_tests_wsl.sh ebreak_test m_trap_test
```

Outputs are written to `build/tests`; checked-in images are not overwritten.
Inspect them before installing:

```bash
less build/tests/ebreak_test.dis
diff -u testdata/ebreak_test.hex build/tests/ebreak_test.hex
```

To copy generated images into `testdata` deliberately:

```bash
bash sim/regress/build_tests_wsl.sh --install ebreak_test m_trap_test
```

Environment variables can select another tool prefix or ISA:

```bash
RISCV_PREFIX=riscv64-unknown-elf- \
RISCV_MARCH=rv32im_zicsr \
RISCV_MABI=ilp32 \
bash sim/regress/build_tests_wsl.sh ebreak_test
```

Relevant Bash grammar:

- `set -euo pipefail` stops on command failure, unset variables, or failed
  pipeline elements.
- `$(command)` captures a command's output.
- `${name}` expands a variable without ambiguity.
- `"${array[@]}"` expands an array while preserving argument boundaries.
- `command -v tool` checks whether an executable is available.
- `a | b | c` forms a pipeline; here `od`, `tr`, and `sed` convert a
  little-endian binary into one 32-bit `$readmemh` word per line.

## Adding a test

1. Add or generate the `.hex` image.
2. Run it directly once with `-Trace` if it is new.
3. Add one object to `tests.json` with a unique name.
4. Choose a timeout based on expected architectural cycles, with margin.
5. Add meaningful tags such as `rv32m`, `lsu`, `csr`, `trap`, or `smoke`.
6. Run the focused tag, then the full smoke suite.

Example:

```powershell
./run_regression.ps1 -Test new_test -Trace
./run_regression.ps1 -Tag smoke
```

## Scope and future adapters

This runner is orchestration, not an official ISA test set. The ACT4 adapter is
documented in `verif/act4/README.md`. Future sources can include legacy
`riscv-tests`, randomized riscv-dv programs, or Spike comparison results. The
basic compile/run/log/report layer remains the same.
