# AR-018 - SoC fabric contract tests

## Status

**The RED contract was added on 2026-08-02. Its two data-access cases are now
GREEN through the AR-019 centralized data fabric; the instruction-access case
remains RED because the instruction interface still has no error response.**

AR-018 is therefore partially satisfied, not closed. The historical 3/3 RED
result remains in
[`evidence/ar018_soc_fabric_red/red_results.txt`](evidence/ar018_soc_fabric_red/red_results.txt).

## Problem

Phase 1 accepted a split 64 KiB map and explicit access-fault behavior, but the
original `riscv_soc` connected every CPU data request directly to data RAM and
connected instruction fetch directly to `prog_ram` without an error signal.
Core-level injected-error tests proved precise CPU traps but could not prove
SoC address classification, local-address translation, or invalid-store side
effect suppression.

## Root causes exposed by the tests

- The original wrapper had no centralized data decoder or return-path mux.
- `data_ram` indexes low address bits, so full architectural addresses could
  alias one physical word when passed directly to it.
- The instruction port still carries read data but no response-error status.
- `prog_ram` still substitutes `0x0010_0073` (EBREAK) for an invalid fetch,
  producing cause 3 rather than instruction-access-fault cause 1.

## Test approach and alternatives

| Option | Decision |
|---|---|
| Reuse core-level injected-error tests | Rejected: bypasses SoC decode and cannot detect aliasing |
| Add a compile-only future-interface test | Rejected: proves interface absence, not architectural behavior |
| Force internal SoC bus signals hierarchically | Rejected: brittle and bypasses retirement behavior |
| Execute firmware through `riscv_soc` and inspect `commit_o` | Selected: covers wrapper, CPU trap path, memory side effects, and completion |

`tb_riscv_soc.sv` instantiates the accepted 16,384-word instruction/data RAM
depths, loads firmware while the CPU is reset, and observes ordered commits. A
committed store to `0x8000_FFFC` reports PASS or a test-specific failure code.
The normal runner gained an optional manifest `top` property; its default is
still `work.tb_riscv_core`.

ModelSim 2019.2 treats a decimal parameter override above signed 32-bit range
as an oversized unsized literal. The runner therefore formats 32-bit address
generics as explicit `32'hXXXXXXXX` values.

## RED-to-GREEN results

| Test | Required behavior | Initial RED | Current result |
|---|---|---|---|
| `soc_unmapped_load_fault` | `0x4000_0000` returns cause 5 with correct `mepc`/`mtval` and no destination/younger write | Failure code 6: RAM serviced the load | **PASS** through the default target |
| `soc_unmapped_store_fault` | cause 7 with correct PC/value and no aliased RAM write | Failure code 6: RAM serviced the store | **PASS**; sentinel at `0x8000_0000` is unchanged |
| `soc_instruction_access_fault_red` | fetch `0x0001_0000` returns cause 1 with `mepc=mtval=0x0001_0000` | Failure code 2 after EBREAK/cause 3 | **Still RED** for the same fetch-interface reason |

The store firmware writes a sentinel to data RAM before attempting the invalid
store, then checks it after the trap. Passing therefore proves both error
signaling and absence of the old high-address RAM alias side effect.

## Reproduction

Run the implemented data cases:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Manifest .\soc_red_tests.json -Tag phase2-data
```

Expected result: 3/3 PASS (including the inserted-wait store variant) and
process exit 0.

Run the isolated remaining fetch RED:

```powershell
./run_regression.ps1 -Manifest .\soc_red_tests.json -Tag phase2-red
```

Expected result: one FAIL, simulator native exit 0, runner process exit 1. The
failure log must still identify out-of-range instruction fetch followed by
EBREAK, not a data-fabric error.

## Remaining acceptance predicate

The data-fabric portion is satisfied by AR-019: full-address classification,
base subtraction, registered response ownership, a one-cycle zero-data error
target, boundary/back-pressure/cross-target tests, and unchanged smoke results.
AR-018 closes only after:

1. instruction fetch carries explicit valid/error response status;
2. invalid fetch produces precise cause 1 without substituting an instruction;
3. `soc_instruction_access_fault_red` becomes GREEN; and
4. broader SoC tests retain the complete regression baseline.

## Consequences

- Data addresses can no longer silently alias RAM outside its configured range.
- The remaining instruction-fault gap is isolated rather than hidden inside a
  mixed three-failure result.
- Detailed AR-019 design and verification evidence is in
  [`AR019_CENTRALIZED_DATA_FABRIC.md`](AR019_CENTRALIZED_DATA_FABRIC.md).
