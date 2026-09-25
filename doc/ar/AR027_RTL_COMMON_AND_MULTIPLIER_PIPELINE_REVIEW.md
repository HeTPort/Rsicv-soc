# AR-027 — RTL Common-Library and Multiplier-Pipeline Review

**Date:** 2026-09-07

**State:** RV32M facade and shared combinational backend implemented and verified;
registered multiplier and common-library growth remain evidence-gated

**Stage:** Post-FreeRTOS structure, timing, and power planning

## Problem

The current SoC is understandable and verified, but `execute.sv` owns several
different combinational concerns and the multiply-high path is the documented
post-synthesis critical path. The project also needs a consistent way to add
future handshake, buffering, CDC, control, and power-management logic without
duplicating small primitives.

CoralNPU's `hdl/verilog/rvv/common` directory demonstrates a mature library of
register, FIFO, handshake, arithmetic, and pipeline helpers. The question is
whether to copy that style broadly now, and whether to register the current
combinational multiplier to align it with the iterative divider.

## Observed evidence

1. [`SEMANTIC_SIGNAL_SPEC.md`](../SEMANTIC_SIGNAL_SPEC.md) already defines the
   project's `_i/_o`, `_q/_d`, request, command, event, pending, candidate,
   owner, and packet conventions. The project does not lack a naming model.
2. `execute.sv` computes signed/signed, signed/unsigned, and unsigned/unsigned
   products combinationally alongside ALU, branch, CSR-data, and exception
   preparation.
3. [`AR017_RADIX2_ITERATIVE_DIVIDER.md`](AR017_RADIX2_ITERATIVE_DIVIDER.md)
   records a 12.605 ns, 19-level multiply-high path through two DSP48E1 blocks
   and carry logic. The reciprocal is about 79.3 MHz, but that is an OOC
   post-synthesis path, not routed Fmax.
4. Exact-board 25 MHz images pass routing with substantial slack. The user's
   recent observation of about 75 MHz is plausible but has not yet been
   retained with exact part, clock constraint, implementation stage, path,
   WNS/TNS, and resource evidence.
5. The core already handles a variable-latency divider and LSU by holding the
   owning ID/EX packet, inserting EX/WB bubbles, and cancelling work on kill.
6. CoralNPU is a much larger Apache-2.0 scalar/vector/matrix design. Its common
   library includes enabled registers, FIFOs, ready/valid controls, arbiters,
   shifters, compressors, floating-point blocks, and a divider. Reusing its
   organizing principle is useful; copying its inventory is not evidence-driven.
7. On 2026-09-13, the arithmetic boundary was moved behind packed
   `rv32m_req_t`/`rv32m_rsp_t` payloads and explicit valid/ready/kill/wait
   semantics. The current multiplier remains zero-extra-latency; the existing
   divider remains iterative and blocking.
8. The three source-level product expressions were replaced by one signed
   33-by-33 product in `rv32m_mul_comb.sv`. Vivado 2019.2 OOC SoC synthesis for
   `xc7z010clg400-1` now reports 4 DSP48E1 cells, versus the 12-cell prior
   implementation recorded by AR-017. Both 16Kx32 memories remain mapped as 32
   RAMB36E1 cells total.
9. The exact-board `hello` build for `xc7z010clg400-1` routed at 25 MHz with
   WNS +17.517 ns, TNS 0, no failed nets, no blocking routed DRC violations,
   and a generated bitstream. It retained 4 DSP48E1 and 32 RAMB36E1 cells.
10. A controlled 100 MHz exact-board route on the same part failed setup timing:
    WNS -0.387 ns, TNS -3.637 ns, and 30 failing endpoints. The worst path is
    ID/EX operand bit 1 to EX/WB multiply result bit 31: 10.183 ns data delay,
    15 logic levels (2 DSP48E1, 11 CARRY4, 1 LUT2, 1 LUT6). Routing completed
    with zero failed nets, so this is an arithmetic-depth failure rather than
    an unrouted-design artifact.
11. The cleanup audit removed display-only x3/x10/x11 ports through regfile,
    core, SoC, board wrapper, and testbenches; four redundant CSR observation
    ports; one retirement observation port; and the assertion-only MRET alias.
    Strict `default_nettype none` is enabled in the changed ownership-boundary
    modules with explicit input net kinds and a `wire` restoration at EOF.

## Root cause

The timing pressure is not caused by the absence of a `common/` folder. It is
caused by the long multiply-high implementation between pipeline registers.
Folder abstraction can improve contracts and reuse, but it cannot shorten a
path unless the architecture inserts state or changes the arithmetic mapping.

Conversely, inserting a register is not a naming refactor. It changes
instruction latency, global stalls, start/exactly-once behavior, kill handling,
writeback timing, performance, and switching activity. The divider and
multiplier need compatible *transaction semantics*, not identical latency.

## Options considered

### Common-library options

1. **Copy CoralNPU's common directory.** Fast-looking structure, but imports
   unused vector/NPU assumptions, Apache provenance obligations, tool risk, and
   unverified semantics. Rejected.
2. **Keep every helper local forever.** Avoids premature abstraction, but will
   duplicate handshake/CDC/storage semantics as peripherals grow. Rejected as
   a permanent rule.
3. **Admit small primitives by contract and demonstrated reuse.** A helper
   enters `src/common/` only with two real consumers or one accepted near-term
   interface, one semantic purpose, a focused test, documented reset/latency,
   and no ISA/domain ownership. Accepted.

### Multiplier options

1. **Keep the combinational multiplier.** Zero extra instruction latency and
   simplest control; acceptable for current 25/50 MHz goals.
2. **Add a registered blocking multiplier.** Likely improves Fmax while
   stalling the small in-order core for one or more cycles. It adds clocked
   state and needs kill/exactly-once verification. Preferred only when a routed
   target or workload justifies it.
3. **Use an iterative shift/add multiplier.** Saves DSP/area in some targets
   but greatly increases MUL latency; useful only if area/power evidence favors
   it.
4. **Instantiate vendor DSP primitives.** Offers deterministic FPGA mapping but
   harms portability; reserve for a vendor wrapper after inferred RTL is
   measured.

## Decision

### 1. Adopt a constrained `src/common/` policy, not a bulk refactor

A common primitive is accepted only when all are true:

- at least two real consumers exist, or an accepted next-phase contract needs it;
- behavior is independent of RV32 instruction meaning and SoC address map;
- latency, reset polarity/type, enable/ready-valid behavior, backpressure, and
  flush/kill response are explicit;
- parameter combinations used by the project elaborate and synthesize;
- a focused test covers reset, hold, transfer, stall, and boundary cases; and
- adding the helper removes semantic duplication rather than merely reducing
  line count.

Likely first candidates are an enabled register, a one-entry ready/valid
register slice or skid buffer, and CDC synchronizer/reset helpers when a second
asynchronous input/domain exists. A generic `adder.sv` is not useful by itself:
plain `+` lets synthesis infer the target carry structure unless explicit
registered/compressor behavior is a measured requirement.

Core-owned packets, retire/trap types, the LSU, divider, and a future RV32M
multiplier remain in `src/core/`; MMIO helpers remain in `src/bus` or
`src/periph`. `common/` is not a miscellaneous folder.

### 2. Keep the existing naming standard and clean violations incrementally

New RTL follows [`SEMANTIC_SIGNAL_SPEC.md`](../SEMANTIC_SIGNAL_SPEC.md). A later
mechanical cleanup may remove mixed-language comments, duplicate local
constants, ambiguous names, and unverified RV64-looking hooks, but each patch
must preserve interfaces or explicitly migrate all producers/consumers/tests.
No second naming convention will be copied from CoralNPU.

### 3. Share the combinational multiplier; do not pipeline it solely to resemble the divider

The implemented `rv32m_unit` facade makes the arithmetic implementation
replaceable, and the shared-product combinational backend remains selected
until either:

- an exact routed target (initially 75 or 100 MHz if desired) fails or lacks
  agreed margin with multiply-high as the real critical path; or
- workload profiling shows a justified frequency/energy/throughput benefit.

The 100 MHz experiment now supplies the required routed timing evidence. Its
failure triggers the registered-backend design gate, but does not authorize a
silent CPI change: the combinational backend remains the production default
until the registered implementation passes the protocol, regression, timing,
and workload-cost gates below.

If the gate triggers, add a registered backend behind the existing core-owned
facade with the same request/response/kill contract:

```text
request:  start + operation + operands
control:  busy + kill
response: complete + result
```

Latency may differ. `start` is accepted once, operands/op are captured, the
ID/EX owner is held while busy, EX/WB receives bubbles until completion, and a
kill produces no completion or architectural side effect. Begin with one
register boundary around the inferred DSP result/post-processing path; add a
second stage only if the new timing report identifies a remaining split.

## Consequences

- The source tree grows only when a verified abstraction has a consumer.
- CoralNPU remains an architectural reference; no Apache source is copied.
- Current behavior and regression claims stay unchanged.
- A registered multiplier can improve Fmax but may increase CPI and clock
  power. Reduced combinational depth/glitching may reduce dynamic energy; the
  net result must be measured as energy per fixed workload, not guessed from
  MHz or watts alone.
- Sharing a multicycle transaction convention makes later iterative or
  pipelined execution units easier without pretending all units have the same
  latency.
- Broader `execute.sv` decomposition may follow ownership boundaries (branch,
  ALU, RV32M unit), but module count is not itself a quality metric.

## Verification required before multiplier implementation is accepted

1. Focused multiplier protocol test: all MUL variants, signed corners, zero,
   maximum values, randomized reference comparisons, back-to-back requests,
   held start, busy, completion pulse, reset, and kill/restart.
2. Pipeline integration: exactly-once retirement, no result after kill, no
   younger effect across trap/redirect, correct RAW and LSU/divider interaction.
3. Preserve all current focused regressions, 23/23 smoke, ACT4 RV32M, Phase 6,
   synthesis, and exact-board gates.
4. Compare LUT/FF/DSP, routed WNS/TNS and critical path at the same target.
5. Compare cycles, runtime, activity-based dynamic power, and energy per fixed
   P0 workload. A frequency gain that increases workload energy without a
   system need is not automatically an improvement.

## Current verification evidence

The 2026-09-13 implementation slice has the following measured evidence:

- focused `rv32m_unit` test: 172 directed/random cases, multiply request and
  divide response backpressure,
  kill/no-response, and restart PASS with zero Questa warnings;
- existing focused divider: 42 cases PASS;
- directed smoke: 23/23 PASS, including normal and delayed data-bus paths;
- official ACT4 RV32M: 8/8 PASS;
- focused FreeRTOS demonstration: 1/1 PASS;
- strict Verilator 5.032 leaf, core, and full-SoC lint PASS with reviewed,
  file-scoped baseline waivers; and
- Vivado 2019.2 AR-003 synthesis: PASS, 4 DSP48E1 and 32 RAMB36E1, zero errors
  and zero critical warnings; and
- exact-board 25 MHz implementation: PASS with WNS +17.517 ns, TNS 0, no
  failed nets, no blocking DRC violations, and a generated bitstream; and
- exact-board 100 MHz implementation: expected gate failure with WNS -0.387 ns,
  TNS -3.637 ns, 30 failing endpoints, and the multiplier path identified above.

The full 47-test ACT4 set, long FreeRTOS soak, and accepted P0 activity-based
power are not claimed by this slice. The 100 MHz measurement justifies starting
a registered multiplier candidate; it does not by itself accept that candidate.

## Learning conclusion

Good reusable RTL is defined by stable timing/ownership/protocol contracts and
tests, not by moving short expressions into a prestigious-looking directory.
Pipeline registers are architectural state: add them where measurement shows a
timing/energy need, and verify their stalls, kills, and retirement behavior as
carefully as the arithmetic result.
