# Divider Digital-Design Learning Lab Architecture

**Phase:** divider-design-lab

**Status:** Verified

**Owner:** project learner

**Last updated:** 2026-09-10

**Depends on:** AR-017

**Related evidence:** [results](results.md)

## Boundary and flow

```text
production radix2_divider.sv (read-only)
  + focused/existing ModelSim TB -> WLF + VCD + validated JSONL
  + Vivado OOC XDC             -> synth DCP -> routed DCP -> timing/netlist reports
  + Verilator lint             -> warning-ID RED/GREEN logs
                                     |
                       generated width-only copy in build/
                                     -> existing 42-case ModelSim TB
```

The production block has one 25 MHz teaching clock, asynchronous active-low
reset, synchronous start/kill control and IDLE/RUN/COMPLETE states. Kill has
priority over start. There are no CDCs, RDC signoff checks or MMIO registers in
this experiment.

Vivado implements the current source OOC for `xc7z010clg400-1`. The clock,
uncertainty and IO delays are teaching constraints, not the board integration
contract. Internal reg-to-reg paths are reported separately from incomplete OOC
boundary paths. A 5 ns requirement is applied to the same routed database only
to teach the distinction between path delay and requirement.

The lint candidate is a generated build artifact containing one explicit-width
cast. A `.vlt` file supplies a signal-specific teaching waiver. Neither replaces
the production source.
