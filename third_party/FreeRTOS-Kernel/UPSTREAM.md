# FreeRTOS Kernel provenance

This directory contains the minimal source subset used by the custom RV32IM
SoC firmware.

- Upstream: <https://github.com/FreeRTOS/FreeRTOS-Kernel>
- Release: `V11.3.0`
- Commit: `9b777ae5c5b8e9e456065a00294d1e5f5f9facf5`
- License: MIT; see `LICENSE.md`
- Imported: 2026-08-16

Included kernel units are `tasks.c`, `queue.c`, `list.c`, `heap_4.c`, the
public `include/` headers, and the unmodified official
`portable/GCC/RISC-V` port. The selected upstream chip extension is
`RISCV_MTIME_CLINT_no_extensions`: this SoC has standard integer registers and
CLINT-compatible `mtime`/`mtimecmp` addresses.

Platform configuration and adaptation live outside this directory under
`sw/apps/freertos_demo/` and `sw/common/linker.ld`. No imported upstream file is
locally modified.
