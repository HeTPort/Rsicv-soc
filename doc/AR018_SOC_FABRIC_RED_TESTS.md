# AR-018 - SoC fabric contract tests

## Status

**The RED contract was added on 2026-08-02. Its two data-access cases are now
GREEN through the AR-019 centralized data fabric. The instruction-access case
is also GREEN: `prog_ram` exposes a registered `fetch_error_o`, the core carries
it through `fetch_pkt_t`, and decode/execute convert it to a precise
`MCAUSE_INST_ACCESS` (cause 1) trap. The focused regression passed on
2026-08-03.**

AR-018 is therefore closed. The historical 3/3 RED result remains in
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
  `prog_ram` now exposes `fetch_error_o` (registered, aligned with
  `instr_data_o`) and the core samples it with the same delayed `{pc, valid}`
  tag it already uses for the instruction word. A fetch error is carried in
  `fetch_pkt_t.error`, decoded into `exc.instr_access_fault`, and given the
  highest priority in the execute-stage trap-cause mux so that a bogus EBREAK
  encoding cannot be misinterpreted as cause 3.
- `prog_ram` still substitutes `0x0010_0073` (EBREAK) for an invalid fetch,
  but the error bit suppresses decode-time exception interpretation and forces
  instruction-access-fault cause 1.

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
| `soc_instruction_access_fault` | fetch `0x0001_0000` returns cause 1 with `mepc=mtval=0x0001_0000` | Failure code 2 after EBREAK/cause 3 | **PASS** (2026-08-03) via `fetch_error_o` and cause-1 priority |

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

Run the isolated fetch-fault case:

```powershell
./run_regression.ps1 -Manifest .\soc_red_tests.json -Tag phase2-fetch
```

Expected result: 1/1 PASS and process exit 0. The committed trap must report
cause 1 with `mepc` and `mtval` equal to the rejected fetch address.

## Acceptance predicate

The data-fabric portion is satisfied by AR-019: full-address classification,
base subtraction, registered response ownership, a one-cycle zero-data error
target, boundary/back-pressure/cross-target tests, and unchanged smoke results.
AR-018 closed after all of the following became true:

1. instruction fetch carries explicit valid/error response status; ✅ implemented
   via `prog_ram.fetch_error_o` and `riscv.instr_fetch_error_i`
2. invalid fetch produces precise cause 1 regardless of replacement data;
   ✅ implemented via `exc.instr_access_fault` and the execute trap-cause mux
3. `soc_instruction_access_fault` becomes GREEN; ✅ PASS on 2026-08-03
4. broader SoC tests retain the complete regression baseline; ✅ smoke 22/22 PASS,
   phase2-data 3/3 PASS on 2026-08-03

### Implementation notes

- `fetch_pkt_t` gained an `error` field; `exc_pkt_t` gained
  `instr_access_fault`. The decode stage now replaces every errored decode with
  `ID_EX_PKT_BUBBLE`, then restores only `valid`, the faulting `pc`, and
  `exc.instr_access_fault`. The replacement instruction, RF/CSR controls,
  operands, memory/redirect controls, MRET/WFI flags, and multiply/divide
  controls are therefore all zero.
- `execute.sv` checks `instr_access_fault_i` first in the trap-cause mux and
  reports `MCAUSE_INST_ACCESS` with `mtval = pc`.
- `riscv.sv` adds `instr_access_fault` to both `wb_trap_event` and `ex_kill`.
  That downstream kill remains defense-in-depth, while the canonical decode
  packet prevents the LSU/divider from classifying replacement data as work in
  the first place.
- `tb_riscv_core.sv` connects the new error signal and guards every assertion
  that compares fetched data against `u_prog_ram.mem` so an invalid fetch does
  not trigger a false mismatch.

### Canonical decode follow-up — 2026-08-23

**Problem/root cause:** Decode previously suppressed only the bogus
instruction's exception interpretation. Other controls still came directly
from the replacement word. The fixed EBREAK replacement did not expose that a
future LOAD/STORE could create false LSU pending state or that a DIV encoding
could assert `div_wait` while `ex_kill` prevented `div_start`.

**Options considered:** Mask each side-effect control individually, add more
downstream kill conditions, or construct one fault-only packet from the
existing canonical bubble. Individual masks are easy to miss when packet
fields grow, while downstream gating retains unnecessary owner/hazard
coupling. Whole-packet canonicalization was selected.

**Decision and consequences:** `decode.sv` first constructs the ordinary
decoded packet. When `fetch_pkt_t.error=1`, its final output instead starts as
`ID_EX_PKT_BUBBLE` and restores only `valid`, `pc`, and
`exc.instr_access_fault`. The packet remains valid so cause 1 reaches
retirement, but its instruction and every normal data/control field are zero.

**Verification:** `run_decode_fetch_error.do` passes at 9 ns with a normal ADDI
control case and fault replacements encoding LOAD, STORE, JAL, branch, CSR,
DIV, MRET, and WFI. All eight fault inputs produce the identical canonical
fault-only packet. The end-to-end `soc_instruction_access_fault` case passes,
and the preservation smoke suite remains 23/23 PASS.

### Coverage scenarios added to the verification plan

| Scenario | Purpose |
|---|---|
| Misaligned control-flow target | Confirm low-order address bits trigger instruction-address-misaligned cause 0, not access-fault cause 1. |
| Fetch above `prog_ram` depth | Confirm out-of-range address triggers cause 1. |
| Consecutive invalid fetches | Confirm the first fault is precise and the redirect to `mtvec` does not fault again before the handler. |
| Invalid fetch followed by a taken branch/redirect | Confirm the stale fetch after redirect is killed. |
| Invalid fetch during a stall | Confirm `if2id` holds the faulting packet and the trap is taken exactly once. |
| Read/write collision on an invalid address | Confirm the error path works with the existing collision bypass. |

### Remaining deferred hardening priority

The following scenarios and interface refinement remain useful but do not
reopen AR-018 or block later work:

- add executable redirect, consecutive-fault, and stall alignment tests for
  the fetch error bit;
- split response-valid from response-error and introduce SoC-level instruction
  decode only when wait states or multiple instruction targets require it.

Priority is deliberately low. Revisit this list when the fetch interface is
next modified or if a directed/random regression exposes a concrete failure.

## Consequences

- Data addresses can no longer silently alias RAM outside its configured range.
- Out-of-range instruction fetches now trap precisely instead of being
  misreported as EBREAK.
- Detailed AR-019 design and verification evidence is in
  [`AR019_CENTRALIZED_DATA_FABRIC.md`](AR019_CENTRALIZED_DATA_FABRIC.md).
