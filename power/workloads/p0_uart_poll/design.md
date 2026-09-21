# `p0_uart_poll` Power Workload Design

## Status and identity

Version `1.0`; lifecycle `verified`: functional tests, exact 95 MHz route,
reviewed block mapping, and two-run repeatability pass. Original bare-metal
image on the split-RAM SoC profile. See [measured results](results.md).

## Purpose

Measure the SoC's CPU-polled UART transmit path for a fixed 14-byte message,
separately from FreeRTOS scheduling and other peripheral activity.

## Design intent

Firmware writes `Hello, UART!\r\n` through the existing `uart_putc` polling
driver and waits until the UART TX engine becomes idle. The 14 bytes are fixed
and decoded independently by the SoC regression. The measurement includes CPU
polling, LSU/fabric MMIO, UART shifter/baud timing, program/data BRAM, and
hardware serialization at the declared 115200 baud and 95 MHz core clock.

## Non-goals

- No UART RX, DMA, interrupt-driven I/O, OS task scheduling, or timer workload.
- No extrapolation to arbitrary throughput, other baud settings, board supply
  rails, or an ASIC UART implementation.
- No CoreMark or general CPU-compute claim.

## Fixed inputs and useful work

The exact message is the 14 bytes of `Hello, UART!\r\n`, without the C NUL
terminator. One work unit is one fully transmitted byte. The serializer must
complete the last stop bit before END, so the fixed window includes all 14
bytes. There is no external RX stimulus.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Warmup / START | Message length and boundary checks pass; committed `0x504F5752` store to ELF-resolved `p0_uart_poll_marker` (`0x80000014` for this image). |
| END | `uart_write` returns after polling all 14 TX writes and `uart_wait_idle` observes the completed final byte; committed `0x454E4421` marker. |
| Final PASS | Firmware stores result count 14 and commits `tohost=1`; the SoC testbench independently decodes the same 14 serial bytes. |

## Expected block activity

| Block | Expected behavior |
|---|---|
| CPU pipeline, program/data BRAM | Driver polling loop and fixed message fetches. |
| LSU/fabric/UART target/TX | Repeated status reads, 14 TX writes, 14 serial frames. |
| Timer interrupt, GPIO, divider | Architecturally idle in-window. |
| Combinational DSP | May switch incidentally; measure rather than assert gated. |

## Functional oracle and failure consequences

The SoC testbench decodes every UART byte and requires the exact 14-byte
sequence before `tohost=1`. Firmware rejects an unexpected message size or
boundary with code `0xBAD75001`. The power testbench independently enforces
single START/END ordering and committed result count 14. A UART mismatch,
timeout, trap, missing marker, or non-PASS `tohost` invalidates the run.

## Key performance indicators

| KPI ID | Metric | Unit | Gate | Evidence |
|---|---|---|---|---|
| P0UART-KPI-001 | Functional oracle | pass/fail | Exact serial decode and power TB PASS | PASS |
| P0UART-KPI-002 | Transmitted bytes | bytes | Exactly 14 | PASS, decoded and committed result |
| P0UART-KPI-003 | Window cycles per byte | cycles/byte | Report; same clock/baud only | 115,574 / 14 = 8,255.2857 |
| P0UART-KPI-004 | Dynamic energy per byte | J/byte | Report for same route | 1.03408e-5 |
| P0UART-KPI-005 | Routed timing/DRC | ns/count | WNS >= 0, TNS 0, blocking DRC 0 | PASS, +0.003 ns / 0 / 0 blocking |
| P0UART-KPI-006 | Activity mapping | pass/fail | >=80% direct or reviewed block alternative | PASS via 12/12 reviewed rules; direct 483/8,762 |
| P0UART-KPI-007 | Dynamic repeatability | percent | <=2% across independent captures | PASS, 0.0% |

## Reproducibility identity

Retain source/ELF/image hashes, compiler/options, message bytes and marker
address, 115200 8N1 setting, clock and timer parameters, 95 MHz routed
checkpoint/part/XDC hashes, ModelSim/Vivado versions, SAIF strip path, block
coverage, vectorless/activity reports, and two-run comparison.

## Risks and limitations

The SoC testbench runs a fast functional UART clock, while `tb_power` and the
routed board design use the 95 MHz/115200 identity; only the latter is a power
input. The metric includes CPU polling and clock infrastructure, not isolated
UART TX energy. RTL SAIF omits glitches, and direct net-name mapping may need
reviewed block coverage and optimized-net bridges.

## Verification and evidence

Firmware build and both functional regressions pass. The SoC scoreboard
decoded 14 correct serial bytes; the power TB observed 115,574 cycles,
31,540 retirements, and committed result count 14. The matching 95 MHz route
passes at WNS +0.003 ns, TNS 0, and zero blocking DRC. Both SAIF imports
pass all 12 reviewed block rules and agree at 0.119 W dynamic, 0.0%
difference. Full evidence and limits are in [measured results](results.md).
