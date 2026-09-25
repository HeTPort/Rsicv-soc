# AR-021 — Polling UART RX with a Parameterized FIFO

## Status

Implemented and verified. The default receive depth is 16 bytes and remains a
module parameter (`RX_FIFO_DEPTH`) so integration can trade buffering against
area without changing the software contract.

## Problem

The Phase 4 UART could transmit bytes, but software could not receive them.
Connecting an asynchronous FPGA pin directly to the bus target would also mix
clock-domain synchronization, serial framing, buffering, and MMIO policy in
one block. A receiver must tolerate software latency because a UART sender
cannot be backpressured once a frame starts.

## Root cause

UART RX is an unsolicited byte stream. The CPU bus is instead a solicited,
single-outstanding request/response protocol. A byte can arrive while the core
is stalled or executing unrelated work, so a one-cycle receive pulse is not a
safe architectural interface. The asynchronous pin must also be synchronized
before any state machine consumes it.

## Options considered

1. **Expose one receive register without a FIFO.** Smallest design, but a
   second byte overwrites the first whenever software is late.
2. **Stall `RXDATA` reads until a byte arrives.** Looks convenient, but lets a
   polling mistake hold the only data-bus transaction indefinitely.
3. **Add an APB UART or import the example packet/CRC UART.** Reuses code, but
   introduces an unnecessary bridge or application-specific protocol.
4. **Use a native core-bus target with a parameterized byte FIFO.** Keeps the
   SoC protocol uniform and gives software bounded latency tolerance.

## Decision

Option 4 is implemented with the following boundaries:

- `uart_rx.sv` owns the two-flop synchronizer and the midpoint-sampling 8N1
  state machine. It emits a one-cycle good-byte event or a framing-error event.
- `core_bus_uart.sv` owns the receive FIFO, sticky error state, and MMIO side
  effects. The FIFO defaults to 16 bytes and explicitly wraps its pointers, so
  non-power-of-two depths are valid.
- Polling is the only software notification mechanism in this phase. UART
  interrupts and a PLIC remain deferred.

The receive policy is deliberately deterministic:

- A good byte is appended if space exists.
- If the FIFO is full, the newly arriving byte is dropped, existing ordered
  data is preserved, and `RX_OVERRUN` becomes sticky.
- A frame with an invalid stop bit is not enqueued and sets sticky
  `RX_FRAME_ERROR`.
- An empty `RXDATA` read completes normally, returns zero, and does not pop.
  Polling software must test `RX_VALID` first.
- Error flags use write-one-to-clear at `RXERROR`. A new hardware error wins
  over a simultaneous software clear, so an event cannot be lost.

## Register contract

All registers require aligned 32-bit accesses. The UART target receives local
offsets after the fabric subtracts `UART_BASE`.

| Offset | Register | Access | Meaning |
|---:|---|---|---|
| `0x00` | `TXDATA` | W | Enqueue low byte; a legal write waits while the TX holding byte is full |
| `0x04` | `STATUS` | R | TX state, RX availability/count, and sticky RX errors |
| `0x08` | `RXDATA` | R | Return and pop the oldest byte; return zero if empty |
| `0x0C` | `RXERROR` | R/W1C | Bit 0 overrun, bit 1 framing error |

`STATUS` fields are:

| Bit(s) | Name | Meaning |
|---:|---|---|
| 0 | `TX_READY` | TX holding byte can accept a write |
| 1 | `TX_BUSY` | Holding byte or serial shifter contains work |
| 2 | `RX_VALID` | At least one byte is available |
| 3 | `RX_FULL` | FIFO count equals configured depth |
| 4 | `RX_OVERRUN` | Sticky dropped-newest indication |
| 5 | `RX_FRAME_ERROR` | Sticky invalid-stop-bit indication |
| 15:8 | `RX_COUNT` | Number of queued bytes, 0–255 |

Unsupported offsets, directions, sizes, and write strobes return a registered
bus error and have no side effects.

## Consequences and guiding principles

- **Synchronize before interpreting.** Metastability containment belongs at
  the asynchronous input boundary, not in downstream control logic.
- **Separate transport from architecture.** The shifter recognizes frames;
  the bus target decides what software observes and when state changes.
- **Buffer unsolicited producers.** A FIFO converts timing-sensitive events
  into an ordered state that polling software can consume.
- **Specify overload behavior.** “FIFO full” is incomplete without defining
  which byte is lost and how software discovers the loss.
- **Make MMIO side effects acceptance-based.** A pop, push, enqueue, or W1C
  action occurs exactly once for the accepted legal bus operation.
- **Do not make polling reads blocking.** A harmless empty result keeps the
  single-outstanding bus recoverable even when software is wrong.

The FIFO reduces but cannot eliminate data loss: at 115200 baud it gives
software roughly 16 character times of tolerance. Board clock accuracy,
clock-domain assumptions, and pin constraints still require physical FPGA
validation.

## Verification evidence

The implementation passed:

- `sim/run_uart_rx.do`: false-start rejection, `00/A5/FF`, and bad-stop
  handling;
- `sim/run_core_bus_uart_rx.do`: empty reads, 16-byte ordering, full/overrun
  drop-newest behavior, framing error, W1C, and invalid accesses;
- `sim/run_core_bus_uart.do` and `sim/run_uart_tx.do`: TX compatibility;
- `sim/run_soc_data_fabric.do`: decode and registered-owner behavior;
- Phase 4 regression 2/2: `Hello, UART!\r\n` TX and a 16-byte pin-to-firmware-
  to-pin RX echo;
- Phase 3 regression 2/2 and smoke regression 22/22;
- Vivado 2019.2 out-of-context synthesis: 0 errors, 0 critical warnings, 32
  `RAMB36E1`, 2 LSU-state cells, and retained UART hierarchy including
  `uart_rx` and `uart_tx`.

Simulation establishes RTL and software semantics. It does not replace the
Phase 7 board gate: an FPGA top, clock/reset conditioning, XDC pin constraints,
and a USB-UART loopback/terminal test are still required.
