# RISC-V Core Refactoring Specification

**Status:** revised and decision-backed
**Target:** RV32IM power-management/control SoC on XC7Z010-class FPGA
**Date:** 2026-09-25
**Supersedes:** the original 63-item undifferentiated refactoring checklist

## 1. Purpose

This specification separates correctness work, measured QoR work, maintainability
cleanup, and optional future architecture. A change is not accepted merely
because it reduces line count, creates a visually regular schematic, or resembles
a larger reference design. Each accepted change needs a stable contract, a real
consumer or measured problem, and verification proportional to its risk.

The current product is a small deterministic RV32IM controller SoC. Its near-term
needs are precise interrupts, dependable peripheral and bus behavior, timing and
energy evidence, safe low-power behavior, sampled-data/DMA expansion, and
verification. Linux-class privilege, RV64, MMU, cache coherence, and vector/NPU
execution are optional later branches, not hidden present requirements.

## 2. Frozen production architecture contract

### 2.1 RV32 is deliberate

- The scalar ISA contract is RV32IM with the implemented Zicsr-style CSR
  instructions and M-mode privileged behavior.
- Integer registers, scalar ALU operands, the CPU-local data bus, addresses, and
  architectural instruction words are 32 bits.
- The repository must not advertise `+define+RISCV_XLEN_64` or module-level
  `AW`/`DW` overrides when the full design cannot implement those settings.
- A future RV64 core would be a separately specified architecture variant with
  its own decode, LSU, CSR, bus, software, ACT, synthesis, and power evidence.
  It is not a parameter value of this core.

RV64 is not required by the power-management target. Wide physical quantities
remain supported explicitly:

- `mtime` and `mtimecmp` remain 64-bit and are accessed as paired RV32 words;
- `mcycle` and `minstret` remain 64-bit for long observation windows;
- future energy/time accumulators may be 64-bit or wider behind RV32 MMIO; and
- accelerator-local vector/MAC datapaths may be wide without changing CPU XLEN.

### 2.2 Genuine parameterization remains

Parameters are retained when multiple values are real, elaboratable contracts:

- RAM address/data/depth parameters remain because the memory modules are
  independent storage primitives and existing flows exercise depth variants.
- The restoring divider may retain an arithmetic data-width parameter because
  its standalone laboratory flow checks multiple widths. The RV32M wrapper uses
  the 32-bit configuration.
- Peripheral capacity/timing parameters such as RAM depth, UART clock/baud/FIFO
  depth, GPIO pin count, timer tick divisor, and verification wait states remain.

Core, fabric, bus-target, and peripheral modules whose ports already use fixed
`riscv_pkg` packet types must not expose shadow `AW`/`DW` parameters.

## 3. Semantic rules

The normative vocabulary remains in `doc/SEMANTIC_SIGNAL_SPEC.md`.

- `flush`: invalidate pipeline storage or a valid bit.
- `kill`: cancel owned in-flight work and suppress any later response/effect.
- `wait`/`busy`: execution-unit ownership or latency state.
- `stall`/`hold`: pipeline movement decision produced by control.
- `complete`: one-cycle completion event; do not replace it with vague `done`.
- `_i`/`_o`: module ports only; `_q`/`_d`: registered/current-next state.

Consequently the original proposals to rename every `kill` to `flush`, every
`wait` to `stall`, and every `complete` to `done` are rejected. Naming cleanup
must improve semantic precision rather than enforce one word globally.

Packed structures are allowed when their fields have one producer, direction,
lifetime, and validity/movement decision. They are not introduced solely to make
the top level appear to have fewer wires.

## 4. Accepted implementation phases

### P0 — Contract honesty and reset-path cleanup

Implement now:

1. Remove the unsupported RV64 macro/opcode/enum hooks from `riscv_pkg.sv`.
2. Remove fake `AW`/`DW` parameters from RV32 core, integration, bus, and
   peripheral modules; retain genuine RAM/divider parameters.
3. Keep 64-bit timers/counters explicit and document their paired RV32 access.
4. Remove reset gating from combinational register-file reads. The state array
   remains reset; no architectural consumer is valid during reset.
5. Preserve existing ISA results, memory map, bus pins, reset polarity, and
   committed-software behavior.

Required verification: focused divider/MDU/LSU/CSR/peripheral tests, directed
smoke, official RV32I/RV32M ACT, strict lint, and synthesis elaboration.

### P1 — Registered multiplier (implemented)

The retained 100 MHz route identifies the multiply-high path as a real timing
problem. Add a backend behind the existing `rv32m_unit` request/response/kill
contract.

The accepted 95 MHz implementation is a registered **blocking** multiplier:

```text
IDLE -> PARTIAL -> REDUCE -> COMBINE -> RESP -> IDLE
          \----------- kill from any state ----------> IDLE
```

Requirements:

- capture operation and operands exactly once;
- fixed, documented small latency;
- one outstanding multiply; no restart while busy;
- stable `rsp_valid` and payload under response backpressure;
- kill produces no response or architectural effect;
- ID/EX owner is held and EX/WB receives bubbles until completion;
- compare the same workloads for routed 100 MHz timing, LUT/FF/DSP, CPI,
  switching activity, dynamic power, and energy per completed workload.

This is not initially a throughput-one pipeline. A fully pipelined multiplier
would require multiple in-flight operations, tags/scoreboarding, and a consumer
able to accept one result per cycle; the present single-issue blocking core has
none of those requirements.

Measured verdict (AR-030): 95 MHz WNS +0.430 ns; 100 MHz WNS -0.312 ns on a
new timer-to-EX/WB path; 4 DSPs retained; `p0_mix` cycles +2.42%, dynamic power
-6.30%, and energy/iteration -4.03%; idle multiplier activity is zero.

### P2 — Control ownership consolidation

`core_ctrl` is not defective merely because it is small. The current core is a
small in-order machine and protocol FSMs remain with their owners. There is,
however, a real ownership mismatch: redirect priority is selected in `riscv.sv`,
EX emits a bare flush request, and MRET redirect timing is split from retirement
state update even though the semantic specification assigns PC/pipeline movement
to control and architectural MRET selection to retirement.

The target contract is:

```text
execute      -- ex_redirect_candidate -->
retire_stage -- retire_redirect -------> core_ctrl --> selected_redirect
decode/EX    -- dependency facts ------>           --> pipe movement decision
LSU/MDU      -- wait/ownership -------->           --> immediate/delayed kills
WFI          -- enter/wait events ------>
```

`core_ctrl` shall own:

- retirement-over-EX redirect priority;
- PC hold and selected redirect delivery;
- IF/ID and ID/EX hold/flush decisions;
- delayed invalidation of stale synchronous instruction-memory responses;
- RAW hazard bubble insertion;
- conversion of older retirement/WFI events into younger-work kill.

A `pipe_ctrl_t` output is permitted because these fields share one owner,
direction, cycle, and movement decision. Individual pipeline registers may
consume only the relevant fields. Do not use this as justification for a
universal pipeline-register module.

`core_ctrl` shall not absorb branch arithmetic, LSU/MDU transaction FSMs, CSR
state updates, interrupt eligibility policy, or future accelerator internals.

This phase needs RED/GREEN tests for simultaneous EX/retirement redirects,
MRET ordering, branch during EX wait, WFI entry/wake, stale fetch return, kill
of LSU/MDU work, and every current hazard case.

Measured verdict (AR-031): implemented and verified. `core_ctrl` now consumes
typed EX/retirement candidates and emits one `pipe_ctrl_t`; MRET target and CSR
restoration meet at retirement. Focused/protocol/smoke/ACT4/lint gates pass.
The exact 95/100 MHz routes close at WNS +0.078/+0.098 ns. Relative to the P1
95 MHz build, P2 costs +121 LUT and -2 FF with unchanged BRAM/DSP. `p0_mix`
cycles and 0.119 W dynamic power are unchanged; the 64-wake WFI workload adds
one cycle across its complete measurement window. The resulting operand-to-
redirect-to-ID/EX-enable path is now the main timing risk for future frequency
or pipeline-depth work.

### P3 — Focused code simplification

The following are accepted only as separate behavior-preserving slices:

- normalize internal names so `_i/_o` is reserved for ports;
- replace repetitive packet packing with one default-zero assignment plus
  explicit meaningful fields, without weakening canonical bubbles;
- extract a pure ALU when it receives a focused arithmetic testbench;
- extract immediate generation only if it improves direct verification;
- extract LSU alignment into local pure functions or a module after its exact
  RV32 lane/error contract is written;
- move CSR effective-read/MEPC forwarding behind a CSR-owned interface;
- move redirect arbitration as specified by P2;
- isolate commit/SVA code only when synthesis configuration or verification
  reuse provides a measurable benefit.

Module count or percentage line reduction is not an acceptance criterion.

**P3 implemented verdict (2026-09-25):** the first accepted slice is verified.
`decode.sv` and `execute.sv` reserve `_i/_o` for ports, remove redundant local
pass-through aliases, and construct ID/EX and EX/WB packets from their typed
canonical bubbles. Fetch-error replacement, LSU merge ownership, ports, stage
count, and cycle behavior are unchanged. Focused/protocol tests, smoke 23/23,
ACT4 47/47, and leaf/core/SoC lint pass. ALU, immediate, and LSU-alignment
extraction remain deferred until each has a focused contract and test; no
line-count or physical-QoR claim is made.

## 5. Common-library policy and CoralNPU comparison

CoralNPU's `hdl/verilog/rvv/common` demonstrates useful typed registers,
ready/valid storage, multi-stage handshake control, FIFOs, arbiters, shifters,
and arithmetic helpers with many real consumers. Its `rvv/com` directory is a
regression-script area, not the reusable RTL library.

Adopt the organizing principle, not its inventory or source:

1. A `src/common` primitive needs two real consumers or one accepted near-term
   contract.
2. Reset, enable, latency, ready/valid behavior, backpressure, flush/kill
   response, and supported parameters must be explicit.
3. A focused test must cover reset, hold, transfer, stall, clear/kill, and
   boundaries as applicable.
4. A module depending on `riscv_pkg` or instruction semantics remains in core.
5. Bus protocol types belong in a bus-owned package if later separated; do not
   create an unscoped `common_pkg` dumping ground.
6. External code is not copied; provenance/licensing rules remain in force.

Near-term candidates are a one-entry ready/valid register slice when a second
consumer appears, and CDC/reset helpers when another asynchronous domain is
accepted. The present three pipeline registers do not yet justify deletion of
their named stage wrappers: IF/ID and ID/EX flush, EX/WB intentionally does not,
and each stage has different architectural observability.

## 6. Future accelerator boundary

Do not route a future NPU/MAC array through `rv32m_unit` or pre-size the scalar
multiplier for it. The workloads and contracts differ.

Preferred system-level path for tensor/neural workloads:

```text
RV32 core -- MMIO command/descriptor --> accelerator control
memory/DMA <-------------------------> local SRAM / MAC array
RV32 core <-- status/interrupt -------- completion and faults
```

This avoids holding the scalar pipeline for long operations and lets the
accelerator choose lane width, accumulator width, quantization, buffering, and
memory bandwidth independently.

If measurement later proves that fine-grained custom instructions are useful,
add a tightly coupled sidecar contract with explicit `req_valid/ready`, typed
payload, `rsp_valid/ready`, fault state, and kill/epoch behavior. Do not add an
unused port before requirements identify instruction encoding, latency,
ordering, memory ownership, and interrupt behavior.

## 7. Deferred or rejected original proposals

| Original rows | Decision |
|---|---|
| 1, 8, 12, 15, 20, 22, 24-26, 31, 33, 53, 57 | Incremental P3 cleanup; no big-bang rename |
| 2 | Reject as RVC mechanism; RVC needs a complete fetch/decode/IALIGN phase |
| 3-6, 11, 48-51, 60 | Apply common-library admission policy; no bulk directory migration |
| 7 | Accepted in P0 with reset/timing verification |
| 9 | Keep fail-closed fetch-error packet construction |
| 10 | Already decided: SystemVerilog throughout |
| 13-14, 36-37, 54-55 | Defer until real CSR/privilege complexity requires new owners |
| 16, 27 | Already implemented by `rv32m_unit` |
| 17 | Reject `BITS_PER_CYCLE` as a substitute for a radix-4 design |
| 18-19, 50 | Keep divider core changes evidence-gated; generic width is legitimate |
| 21, 28, 32 | Reject global kill/flush, wait/stall, complete/done renaming |
| 23 | Keep `magnitude`; `to_unsigned` would misdescribe absolute-value behavior |
| 29, 34, 61 | Superseded by fixed RV32 contract and P0 cleanup |
| 30 | Accepted as P1, but as a real backend rather than a decorative latency parameter |
| 35 | Add LSU downstream ready only with a real EX/WB backpressure consumer |
| 38, 63 | Do not parameterize architectural/trace widths without a product requirement |
| 40-43 | Defer S/U mode, delegation, and PMP to a Linux/privilege phase; no empty shells |
| 44 | Valid later performance phase after registered-multiplier attribution is complete |
| 45, 56 | Accepted as P2 control/completion ownership work |
| 46, 59, 62 | One duplicate proposal; permit a semantic `pipe_ctrl_t` only under P2 contract |
| 47 | Reject: WFI must remove younger live instructions before logical wait |
| 52, 58 | Optional verification/production-configuration work, not automatic area reduction |

## 8. Change and verification discipline

Each phase must update the living knowledge base, decision record, focused AR
evidence, phase requirements/architecture/verification/results, diagrams, and
open risks. Expected results are never proof.

At minimum, behavior-preserving refactors run focused affected tests, 23/23
directed smoke, applicable 47/47 ACT, and strict lint. Timing-sensitive changes
also run identical-part/constraint synthesis and route comparisons. Power claims
use identical fixed workloads and report energy, not frequency alone.

## 9. Remaining work, in priority order

### Do next

1. **Protect the verified baseline.** Keep smoke 23/23, ACT4 47/47, focused
   control/LSU/RV32M tests, and layered lint as mandatory gates for every core
   change.
2. **Close the product clock claim.** The current exact build passes 100 MHz by
   only +0.098 ns. Before advertising 100 MHz as guaranteed, repeat route seeds
   and relevant temperature/voltage corners, confirm the actual board speed
   grade, and perform physical-board validation. Until then, 95 MHz is the
   evidence-backed production target.
3. **Advance the power-management roadmap.** Use the existing P0 measurements
   as baseline, then specify P1 safe clock-enable/sleep counters, C0 low-energy
   fault/watchdog/control behavior, M0 versioned plant modelling, and C1 sampled
   data/ADC/DMA timing. Each becomes active only with measurable safety, latency,
   wake, and energy requirements.
4. **Strengthen verification reuse.** Complete the U0 passive retirement/trap
   monitor and ordered scoreboard, then add ISS differential testing in U1/U2.

### Do only when a focused need appears

- Extract ALU, immediate generation, LSU alignment, or CSR effective-read logic
  only after adding a dedicated contract and focused test for that boundary.
- Add forwarding, caches, DMA, custom instructions, or an accelerator only
  after workload profiling identifies the bottleneck and defines ordering,
  memory ownership, fault, interrupt, and kill behavior.
- Consider manual floorplanning only after the architecture stabilizes and a
  reproducible routed path fails its declared clock target.

### Explicitly not required now

- RV64 support or scalar-width parameterization.
- Parameterized multiplier pipeline depth or arbitrary divider cycle count.
- Pre-wired NPU/MAC ports, copied CoralNPU library structure, or speculative
  vector state.
- Code extraction whose only evidence is fewer lines or a tidier schematic.
