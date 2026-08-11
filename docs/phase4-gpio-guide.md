# Phase 4 GPIO Guide

The Phase 4 GPIO slice is a deliberately small output-only peripheral. It is
enough to drive LEDs in a future board top while keeping the bus contract easy
to understand and verify.

## Software view

| Address | Register | Access | Meaning |
|---:|---|---|---|
| `0x1000_1000` | `GPIO_OUT` | R/W | Persistent 32-bit output state; implemented pins use its low `GPIO_WIDTH` bits |

The default `GPIO_WIDTH` is eight and the default reset value is zero. Byte,
aligned halfword, and aligned word accesses are supported. A write updates
only the lanes selected by the size-consistent strobes. Unsupported or
malformed accesses return an error without changing pins.

## Hardware ownership

```text
firmware -> LSU -> data fabric -> core_bus_gpio -> gpio_out_o -> board top/XDC
```

- The fabric owns full-address decode, base subtraction, and delayed-response
  ownership.
- `core_bus_gpio` owns access legality, the persistent output register, partial
  write merging, and the registered response.
- `riscv_soc` instantiates the target and exports `gpio_out_o`.
- A future board top will bind those logical bits to physical package pins.

Keeping these roles separate prevents top-level signal cleanup from turning
into hidden behavioral coupling.

## Verification

From `sim/`:

```powershell
vsim -c -do run_core_bus_gpio.do
vsim -c -do run_soc_data_fabric.do
```

From `sim/regress/`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run_regression.ps1 -Manifest .\phase4_tests.json -Test soc_gpio_out
```

The firmware writes and reads back `0x01`, `0x02`, `0x04`, `0x08`, and
`0xA5`. The testbench separately watches `gpio_out_o`, so a correct bus
readback with a broken external output connection cannot falsely pass.

An FPGA board is not required for these RTL checks. Physical completion still
requires a board-specific top, clock/reset definition, XDC pin assignments,
I/O voltage selection, bitstream generation, and observation of real LEDs.

Detailed rationale and RED/GREEN evidence are in
[`AR022_MEMORY_MAPPED_GPIO_OUTPUT.md`](../doc/AR022_MEMORY_MAPPED_GPIO_OUTPUT.md).
