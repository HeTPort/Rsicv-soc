# P2 Core Control Ownership Architecture

**Phase:** p2-core-control-ownership
**Status:** Implemented and verified
**Owner:** RTL architecture
**Last updated:** 2026-09-25
**Depends on:** `redirect_t`, canonical bubbles, precise retirement
**Related evidence:** [AR-031](../../ar/AR031_CORE_CONTROL_OWNERSHIP.md)

## Boundary and data flow

```text
execute      -- branch/jump redirect_t candidate --+
retire_stage -- trap/IRQ/MRET redirect_t ----------+--> core_ctrl
decode/EX    -- dependency and exception facts ----+       |
LSU/RV32M    -- wait -------------------------------+       +--> selected redirect_t
WFI          -- enter/wait -------------------------+       +--> pipe_ctrl_t
                                                               |  PC/fetch action
                                                               |  IF/ID hold/flush
                                                               |  ID/EX hold/flush
                                                               +  pipe/EX kill
```

`retire_stage` remains the architectural selector. `execute` calculates only
branch/jump candidates. `core_ctrl` arbitrates already-formed candidates and
owns movement/cancellation actions. LSU and RV32M remain protocol owners.

## Interface contract

- `redirect_t ex_redirect_i`: taken branch/JAL/JALR candidate from EX.
- `redirect_t retire_redirect_i`: trap/interrupt/MRET decision from retirement.
- `redirect_t redirect_o`: retirement candidate if valid, otherwise EX.
- `pipe_ctrl_t pipe_ctrl_o`: same-cycle PC/fetch/stage movement and kill actions.
- `exc_pkt_t ex_exc_i`: facts used only to cancel local EX-owned work.

`pipe_ctrl_t` is justified because every field has one owner, one direction,
and the same cycle-level movement decision. It is not a generic pipeline bus.

## Priority and timing

```text
redirect_o = retire_redirect_i.valid ? retire_redirect_i : ex_redirect_i
pipe_kill  = retire_redirect_i.valid || wfi_enter_i
ex_kill    = pipe_kill || valid EX exception
```

Immediate IF/ID and ID/EX flush uses the selected redirect. A registered
`fetch_kill_q` invalidates the single stale response returned by synchronous
instruction memory on the following cycle. RAW hazard holds PC/IF-ID and
inserts one ID/EX bubble only when EX can advance. EX wait holds PC, IF/ID, and
ID/EX without flushing the owning instruction.

The MRET target is captured in the existing `ex_wb_pkt_t.next_pc`. On
retirement, `retire_stage` issues both `csr_retire_cmd.mret` and
`REDIRECT_MRET`; this moves MRET redirect one stage later but makes
architectural ownership atomic without adding a redundant packet field.

## Clock, reset, CDC, and safe state

No new clock domain. Only delayed fetch invalidation is stateful in
`core_ctrl`; reset clears it. Invalid redirects and canonical pipeline bubbles
are all zero. Movement outputs are combinational functions of registered stage
facts and unit wait levels.

## Alternatives

- Keeping redirect muxing in `riscv.sv` was rejected because composition would
  continue owning policy.
- Moving LSU/RV32M FSMs into control was rejected because transaction state is
  local protocol ownership, not pipeline policy.
- Keeping immediate EX-stage MRET was rejected because PC movement and CSR
  restoration would remain split across architectural boundaries.
- A universal pipeline register/control wrapper was rejected because IF/ID,
  ID/EX, and EX/WB do not share identical flush semantics.

## Physical consequence

The selected redirect must affect PC and younger-stage enables in the same
cycle. On the current FPGA this creates the measured operand -> branch target/
decision -> redirect arbitration -> ID/EX enable path. It closes 100 MHz with
0.098 ns WNS but is the correct boundary to pipeline or restructure if future
frequency, prediction, or pipeline-depth requirements exceed that margin.
