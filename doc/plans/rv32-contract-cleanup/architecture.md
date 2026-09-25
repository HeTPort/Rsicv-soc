# RV32 Contract Cleanup Architecture

**Phase:** rv32-contract-cleanup
**Status:** Verified
**Owner:** RTL architecture
**Last updated:** 2026-09-24
**Depends on:** AR-017, AR-027
**Related evidence:** [AR-029](../../ar/AR029_RV32_CONTRACT_AND_REFACTORING_SCOPE.md)

## Boundary

```text
riscv_pkg: AW=32, DW=32, XLEN=32
    |-- RV32 core packets, CSR, LSU, MDU facade
    |-- 32-bit single-outstanding core bus
    |-- timer/UART/GPIO/RAM adapters
    +-- 64-bit timer/counter state via paired RV32 words

generic leaf IP retained:
    radix2_divider(DW)     prog_ram(AW,DW,DEPTH)     data_ram(AW,DW,DEPTH)
```

No clock, reset polarity, CDC boundary, memory map, state machine, instruction
latency, or bus transaction timing changes. The register-file state array keeps
its asynchronous reset; only combinational read reset gating is removed.

## Future accelerator boundary

Wide accelerator data is independent of XLEN. The preferred NPU/MAC connection
is SoC-level MMIO command/status plus DMA/local SRAM. A tightly coupled custom
instruction sidecar is deferred until latency, ordering, memory ownership,
fault, and kill/epoch requirements exist.

## Alternatives

See AR-029. Completing RV64 and leaving false hooks were rejected.
