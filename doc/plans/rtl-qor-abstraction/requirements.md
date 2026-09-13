# RTL QoR and RV32M Abstraction Requirements

**Status:** Implemented and verified for the initial vertical slice

## Scope

This phase implements the first AR-027 vertical slice: a replaceable RV32M
boundary, a single-product combinational multiplier backend, focused protocol
verification, layered lint inputs, and measurement/documentation updates.

## Requirements

| ID | Requirement | Failure consequence |
|---|---|---|
| RQA-REQ-001 | Preserve RV32IM architectural results and ordered retirement behavior. | Software-visible regression. |
| RQA-REQ-002 | A request transfers only when request valid and ready are both asserted. | Lost or duplicated operation. |
| RQA-REQ-003 | A response remains valid with stable data while response ready is low. | Corrupted variable-latency result. |
| RQA-REQ-004 | A kill cancels accepted, unretired work and prevents a later response. | Wrong-path architectural side effect. |
| RQA-REQ-005 | The initial facade permits at most one outstanding RV32M operation. | Ordering ambiguity in the blocking pipeline. |
| RQA-REQ-006 | MUL, MULH, MULHSU, and MULHU use one shared extended multiplication expression. | Redundant inferred multiplier hardware remains. |
| RQA-REQ-007 | Existing divider arithmetic and divide-by-zero/overflow behavior remain unchanged. | ISA non-compliance. |
| RQA-REQ-008 | Production lint can be run without compiling testbench sources. | Integration warnings remain obscured by verification code. |
| RQA-REQ-009 | QoR claims use the same FPGA part, constraints, and implementation stage. | Invalid optimization comparison. |

## Non-goals

- No registered multiplier is accepted in this phase without a routed timing
  or accepted activity-based energy trigger.
- No register-file, LSU, memory, peripheral, or DFX restructuring is included.
- The existing external debug ports remain until their testbench consumers are
  migrated in a separate change.
- The incomplete P0 SAIF report is not treated as proof of power improvement.

## Assumptions

- The implemented core remains RV32-only (`DW == 32`).
- The pipeline remains in-order and blocking for divide operations.
- ModelSim/Questa and Vivado 2019.2 compatibility takes precedence over use of
  synthesizable SystemVerilog interfaces.
