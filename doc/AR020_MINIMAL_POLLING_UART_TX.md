# AR-020 — Minimal Polling UART TX

**Date:** 2026-08-09

**State:** Verified in RTL simulation and out-of-context synthesis

**Stage:** Phase 4 UART vertical slice; GPIO and physical-board validation remain open

## Problem

The SoC had CPU, RAM, timer, and precise traps, but no externally observable
character output. Importing the available example UARTs would also import
packet framing, CRC, ad-hoc timing, or APB assumptions that do not match the
project's native single-outstanding core bus.

## Root cause

The serial engine and CPU bus operate at different rates and have different
ownership rules. A CPU store is a transaction; a UART frame remains busy for
ten bit periods. Connecting a store directly to a shift register would either
drop writes while busy or force serial timing details into the fabric.

## Options considered

1. **Import the packet/CRC UART examples.** Rejected: they use unrelated
   framing, contain an unsuitable baud calculation, lack the required native
   handshake, and have unclear reuse/licensing provenance.
2. **Wrap the APB UART.** Rejected for this milestone: an APB bridge adds a
   second protocol without providing value to the one-master SoC.
3. **Direct register-to-shifter design.** Small, but has only one-byte capacity
   and awkward simultaneous completion/write behavior.
4. **One-byte holding register plus active shifter.** Selected: the bus target
   owns the queued byte, the shifter owns the active byte, and `valid && ready`
   is the only ownership-transfer event.

## Decision

- Implement TX-only, parameterized 8N1. RX, UART interrupts, CRC, packet
  framing, and PLIC are deferred.
- Decode `0x1000_0000..0x1000_0fff` in `soc_data_fabric` and send the UART
  target base-subtracted local addresses.
- Define word registers:
  - `TXDATA +0x00`: write-only; low byte is queued.
  - `STATUS +0x04`: read-only; bit 0 is `TX_READY`, bit 1 is `TX_BUSY`.
- A legal TXDATA write backpressures when the holding slot cannot accept. It is
  not an error and is never dropped.
- Unsupported offset, size, direction, or write strobe receives one registered,
  side-effect-free error response.
- Add `TARGET_UART` to the registered fabric response-owner mux. Live CPU
  addresses are irrelevant after a target accepts a request.
- Use rounded integer clocks per bit:
  `(CLK_FREQ_HZ + BAUD_RATE/2) / BAUD_RATE`; require at least two clocks/bit.
- Default hardware parameters are 25 MHz and 115200 baud. Tests may use a
  smaller equivalent ratio to reduce simulation time.

## Signal and ownership flow

```text
CPU store/load
    |
    v
soc_data_fabric -- registers TARGET_UART at request acceptance
    |
    | local offset 0x00/0x04
    v
core_bus_uart -- registered response + one-byte holding register
    |
    | tx_valid && tx_ready transfers one byte
    v
uart_tx -- active 10-bit {stop,data,start} frame
    |
    v
uart_tx_o -- idle high, start low, data LSB-first, stop high
```

The holding slot may accept a replacement byte in the same cycle its old byte
moves into an idle shifter. Therefore `TX_READY` means “a write can transfer
now,” not merely “the holding-full bit is zero.” `TX_BUSY` means either the
shifter or holding register owns a byte.

## Consequences

- The CPU can use a simple polling driver, while target backpressure provides a
  lossless safety layer if software writes at the readiness boundary.
- Effective capacity is two bytes: one active frame and one queued byte.
- The core, retirement architecture, and interrupt logic do not change.
- The UART window no longer falls through to the default error target; GPIO
  and other unimplemented regions still do.
- Integer division introduces baud error when the clock is not an exact baud
  multiple. The exact board clock must be used when selecting final parameters.

## Verification evidence

- Canonical map generation/check and 9/9 generator unit tests: PASS.
- `vsim -c -do run_uart_tx.do`: exact 8N1 frames for `00`, `A5`, `FF`: PASS.
- `vsim -c -do run_core_bus_uart.do`: legal/error responses, queueing,
  backpressure, simultaneous dequeue/enqueue, ordered bytes: PASS.
- `vsim -c -do run_soc_data_fabric.do`: UART local translation and registered
  response ownership: PASS.
- Phase 4 `soc_uart_hello`: CPU polling firmware emitted
  `Hello, UART!\r\n`; the serial-pin decoder checked all 14 bytes: PASS.
- Phase 3 timer/WFI tests: 2/2 PASS, including 10,000 interrupts.
- General directed smoke: 22/22 PASS.
- Vivado 2019.2 OOC on provisional `xc7z010clg400-1`: 0 errors, 0 critical
  warnings, 32 BRAM cells, 2 LSU-state cells, and 72 UART-hierarchy cells.

## Remaining hardware gate

No FPGA connection is required for the evidence above. Physical validation
requires the exact board/part, actual input clock and reset, UART TX package
pin, I/O bank voltage/IOSTANDARD, constraints, and a USB-UART/terminal setup.
Those facts cannot be inferred safely from “XC7Z010” alone.

## Long-term learning principles

1. Buffer ownership and protocol ownership are architecture, not cosmetic RTL.
2. Normal resource occupancy should apply backpressure; errors describe invalid
   operations.
3. Register maps are hardware/software ABIs and should have one generated
   source of truth.
4. A bus-level test and a pin-waveform test prove different failure classes.
5. Simulation proves logic; synthesis proves mapping; hardware proves clocks,
   pins, voltage, and physical tolerance.
