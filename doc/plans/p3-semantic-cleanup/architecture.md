# P3 Semantic Cleanup Architecture

**Phase:** p3-semantic-cleanup
**Status:** Implemented and verified
**Owner:** RTL architecture
**Last updated:** 2026-09-25

## Construction rule

```text
module ports: *_i / *_o
local aliases: semantic name without direction suffix

packet = CANONICAL_BUBBLE
packet.field = meaningful local value
...
```

Decode first forms an ordinary decoded packet, then the existing fetch-error
override replaces it with a fault-only canonical packet. Execute first computes
ALU/control/trap facts, then forms one EX/WB packet whose memory-completion fields
remain zero until the LSU-owned completion merge in `riscv.sv`.

The change does not alter clocks, resets, CDC/RDC, state, stage boundaries,
numeric formats, faults, redirect priority, or unit handshakes.

Implementation is deliberately limited to `decode.sv` and `execute.sv` local
naming/construction. No module split, new shared primitive, packet type change,
or data/control-path boundary was introduced, so the repository architecture
diagrams remain current.
