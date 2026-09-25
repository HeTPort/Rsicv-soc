# P1 Registered Blocking Multiplier Architecture

**Phase:** p1-registered-multiplier
**Status:** Implemented
**Last updated:** 2026-09-25

## Boundary and data flow

```text
ID/EX packet -> rv32m_unit -> rv32m_mul_reg
                  |              IDLE: capture request
                  |              PARTIAL: 4 registered 17-bit products
                  |              REDUCE: 2 registered aligned sums
                  |              COMBINE: registered 66-bit product
                  |              RESP: stable selected RV32 result
                  +-----------> execute -> EX/WB -> retire
                  |
                  +-----------> unchanged radix2_divider

mul/div wait -> ex_wait -> core_ctrl -> hold PC, IF/ID, ID/EX
pipe/EX kill ---------------------> rv32m_unit/backends
```

## State and timing

`IDLE -> PARTIAL -> REDUCE -> COMBINE -> RESP -> IDLE`. The accept edge
captures `rv32m_req_t`. Three arithmetic clocks later the registered product
enters RESP. With the current always-ready sink, ID/EX and EX/WB advance on the
next edge: four added core cycles per accepted MUL, exactly matching the 8,192
cycle increase for 2,048 `p0_mix` iterations.

The 33-bit signedness extension is split into 17-bit low and signed 16-bit high
halves. Four DSP-sized products are registered, aligned into two registered
66-bit sums, then combined. Request/datapath registers change only during an
accepted MUL transaction, preventing non-MUL ID/EX activity from toggling the
multiplier cone.

## Control constraints

- `wait_o` does not depend on `kill_i`; this avoids a loop through interrupt
  deferral, retirement redirect, pipe kill, and arithmetic cancellation.
- `req_ready` and `rsp_valid` are suppressed by kill.
- Divider and multiplier cannot own the single facade simultaneously.
- The response cycle releases the pipeline only when the response is accepted.

## Clocks, reset, faults, and CDC

One existing core clock and active-low asynchronous reset; no CDC. Reset/kill
clear protocol state. Datapath registers are not reset because their contents
are invalid outside the state machine; this also avoids asynchronous controls
at DSP boundaries. Arithmetic has no independent fault response; instruction
legality remains decode-owned.

## Alternatives

See AR-030. Arbitrary latency knobs and throughput-one multiplication are not
part of this phase.
