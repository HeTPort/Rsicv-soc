# RTL QoR and RV32M Abstraction Architecture

**Status:** Implemented

## Boundary

`rv32m_unit` owns operation classification, request acceptance, divider
lifetime, kill behavior, response backpressure, and result selection.
`execute` receives only a completed RV32M result. The core top-level combines
the unit's pending state with LSU ownership for the existing generic EX wait
path.

```text
ID/EX packet
   | operation + operands
   v
rv32m_unit ---- kill
   |       \
   |        +-- radix2_divider
   +-- rv32m_mul_comb (single extended product)
   |
   +-- valid/ready response --> execute --> EX/WB
```

## Interface semantics

- Request acceptance: `req_valid_i && req_ready_o`.
- Response acceptance: `rsp_valid_o && rsp_ready_i`.
- Request payload must remain stable while valid and not ready.
- Response payload remains stable while valid and not ready.
- Multiply may return combinationally in the acceptance cycle.
- Divide holds ID/EX until its response is available.
- `kill_i` prevents new work, cancels divider state, clears held response state,
  and suppresses the externally visible response.

## Numeric formats

The multiplier sign-extends each RV32 operand to 33 bits according to the
operation and performs one signed 33-by-33 multiplication. MUL selects bits
31:0. The three high variants select bits 63:32. The leading extension bits
make unsigned operands positive in the shared signed multiplier.

## Reset and clocks

The facade and divider use `clk_i` and asynchronous active-low `rst_ni`.
Only response-hold/protocol state is reset; the combinational multiplier has no
state. No new clock domain or CDC path is introduced.

## Alternatives

- Three parallel products: rejected for this candidate because it exposes
  redundant arithmetic to synthesis.
- Registered multiplier: deferred until measurement justifies its CPI change.
- Vendor DSP primitive: deferred to preserve portability.
