# AR-024 — ZYNQ MINI REVB FPGA Integration

**Date:** 2026-08-15; UART/FreeRTOS/reset follow-up 2026-08-23
**State:** Implemented; routed builds plus UART, FreeRTOS, LED/timer, and repeated-reset hardware evidence verified
**Stage:** Phase 7

## Problem

AR-023 proved that the Phase 5 ELF-derived program and data images initialize
both SoC BRAM banks, but only at the out-of-context `riscv_soc` boundary. The
repository had no exact board identity, physical top, pin constraints,
clock/reset conditioning, routed timing evidence, or reproducible bitstream
flow. It therefore could not separate a CPU/firmware failure from a board-level
clock, reset, pin, or serial-wiring failure.

The supplied board is a Bo Chen Jing Xin ZYNQ MINI marked `20240221/REVB`. Its
device is marked XC7Z010 CLG400, but no readable speed-grade suffix is visible.

## Schematic and board findings

The supplied schematic and front/back photographs establish this first PL
interface:

| Function | Package pin | Board signal | Electrical behavior |
|---|---:|---|---|
| PL clock | K17 | `PL_CLK_50M` / X1 | 50 MHz, Bank 35, LVCMOS33 |
| Reset | M20 | `FPGA_PL_KEY1` / PL K2 | active low, external 4.7 kohm pull-up |
| LED 0..3 | T12/U12/V12/W13 | PL D1..D4 | active high, LVCMOS33 |
| UART RX | U15 | EXT IO U15 | external adapter TX to FPGA |
| UART TX | W15 | EXT IO W15 | FPGA to external adapter RX |

Banks 34 and 35 use 3.3 V VCCO. The onboard CH340 serial bridge is connected
to PS MIO48/MIO49, so it cannot carry the custom PL UART. The PL UART therefore
requires a separate 3.3 V TTL adapter with crossed TX/RX and common ground;
adapter VCC remains disconnected.

## Options considered

1. Generate the SoC clock from a Zynq PS FCLK. Rejected for the first target
   because K17 already supplies a direct PL clock and PS initialization would
   add an unnecessary clock dependency.
2. Divide 50 MHz with fabric logic. Rejected because a fabric-generated clock
   would complicate clock routing and timing.
3. Use a generated Clocking Wizard IP. Viable, but not selected because a
   direct `MMCME2_BASE`/`BUFG` wrapper is smaller and reproducible without
   generated project state.
4. Target an assumed faster device. Rejected because the visible package mark
   does not prove the speed grade.
5. Waive the routed combinational-loop DRC. Rejected because Vivado explicitly
   states that the loop can race and invalidates timing accuracy.

## Decision and implementation

`fpga/zynq_mini_revb/top.sv` is the board boundary. An MMCM multiplies the
50 MHz K17 input by 20 and divides by 40, producing a conservative 25 MHz core
clock. Reset asserts from PL K2 or MMCM lock loss and deasserts after four
25 MHz edges. UART RX already has its own two-flop synchronizer in `uart_rx`.

The wrapper keeps `GPIO_WIDTH=8` because Phase 5 firmware reads back `0xA5`,
while only `gpio_out[3:0]` reaches the four physical LEDs. The programming port
is tied inactive and `load_done=1`, so the core boots directly from bitstream-
initialized program/data BRAM.

A retained but otherwise unused `PS7` hard macro satisfies Zynq device
configuration. It supplies no application clock, bus, firmware, or ARM
service; the custom RISC-V SoC remains entirely in programmable logic.

`fpga/zynq_mini_revb/build.tcl` selects conservative part
`xc7z010clg400-1`, reads the explicit RTL/XDC sources, binds both images,
checks nonzero program/data BRAM initialization, synthesizes, places, routes,
reports utilization/timing/clock/power/DRC, rejects negative WNS or blocking
DRCs, and writes a compressed bitstream. It accepts `hello`, `timer_gpio`, or
`timer_irq`. Application-specific `mtime` prescalers keep the firmware images
unchanged but make LED and interrupt activity visible on hardware.

## Routed failure found and fixed

The first routed `hello` attempt exposed `LUTLP-1`: nine LUTs formed a feedback
loop through retirement interrupt selection, `pipe_kill`/`ex_kill`, and the
same-cycle LSU/divider wait signals.

The root cause was that `retire_stage` uses `ex_wait` to defer an interrupt,
while the wait observations themselves included `!ex_kill`. Selecting the
interrupt asserted the kill, the kill removed the wait, and removing the wait
selected the interrupt again.

The fix separates visible ownership from start/cancel permission:

- `lsu.busy_o` now observes a pending aligned memory operation independently
  of same-cycle kill, while `mem_start` still requires `!ex_kill_i`;
- `div_wait` now observes the incomplete divider instruction independently of
  kill, while `div_start` and the divider state machine still honor kill.

Redirect priority, pipeline flush, bus-request suppression, and registered
owner cancellation are unchanged. No DRC waiver is used.

## Verification evidence

Post-fix simulation:

- focused LSU protocol: PASS;
- focused retirement stage: PASS;
- Phase 3 WFI manifest: 1/1 PASS;
- Phase 5 firmware manifest: 4/4 PASS.

Vivado 2019.2 exact-board results on `xc7z010clg400-1`:

| Image | Timer prescaler | Routed WNS | TNS | DRC errors | Bitstream |
|---|---:|---:|---:|---:|---|
| `hello` | 1 | +22.824 ns | 0.000 ns | 0 | generated |
| `timer_gpio` | 1,250,000 | +22.093 ns | 0.000 ns | 0 | generated |
| `timer_irq` | 25,000 | +22.555 ns | 0.000 ns | 0 | generated |

All three builds retain 16 initialized program plus 16 initialized data
RAMB36E1 cells. The utilization envelope is 3,978-3,984 LUTs
(22.60-22.64%), 2,852-2,873 registers (8.10-8.16%), 32/60 BRAM tiles
(53.33%), 12/80 DSPs (15%), two BUFGs, and one MMCM.

Physical-board results through 2026-08-23:

| Image/path | Result | Observation |
|---|---|---|
| FT232HL JTAG | PASS after runtime repair | Vivado programmed the XC7Z010 |
| `timer_gpio` | PASS | `0001 -> 0010 -> 0100 -> 1000 -> 0101` on D1-D4 |
| `timer_irq` | PASS | binary interrupt count 1 through 10; final `1010` |
| `hello` | PASS | exact external 115200 8N1 output observed on W15 through a 3.3 V USB-TTL adapter |

The initial Hardware Manager symptom was `localhost (0)`: local servers were
connected, but no cable target was enumerated. Windows nevertheless saw
FT232H `VID_0403:PID_6014` with the bus description `Digilent USB Device`.
Inspection found the Vivado-bundled Digilent installer but no installed Adept
runtime. `install_drivers_wrapper.bat` installed Xilinx PC USB support,
Digilent Adept Runtime 2.18.2/USB support, and SmartLynq support; the log ended
successfully, and board programming then worked. The full evidence trail,
commands, source research, and reusable diagnostic decision tree are recorded
in [`ZYNQ_MINI_REVB_JTAG_BRINGUP_LOG.md`](ZYNQ_MINI_REVB_JTAG_BRINGUP_LOG.md).

## Consequences and open risks

- No board connection is needed for RTL, constraints, synthesis,
  implementation, timing reports, BRAM checks, or bitstream generation.
- JTAG/cable discovery, oscillator/BRAM boot, LED polarity, GPIO, timer
  progression, timer interrupts, external UART TX, production FreeRTOS, and
  repeated PL reset now have physical evidence.
- The real speed grade remains unidentified. `-1` is the conservative build
  assumption and must not be rewritten as a confirmed package property.
- Vivado warns that asynchronously reset registers feed data-BRAM
  address/control cones (`REQP-1839`). Reset deassertion is synchronized and
  deliberate K2 restart testing now passes physically, but the structural
  warning remains a future cleanup candidate and must not be suppressed.
- DSP pipeline warnings are accepted at 25 MHz because routed slack is large;
  50 MHz remains a separate optimization/closure decision.
- Vectorless PS7 power is approximate because the retained PS7 macro is not
  configured for application use.

## Physical completion checklist

1. [x] Set board BOOT to JTAG `00`, discover the cable/device, and program it.
2. [x] Observe the expected `timer_gpio` LED sequence.
3. [x] Observe ten `timer_irq` counts and the final `1010` state.
4. [x] Connect a 3.3 V TTL adapter: TX->U15, RX<-W15, GND->GND, no VCC.
5. [x] Observe exact `Hello, UART!\r\n` at 115200 8N1.
6. [x] Repeat PL K2 reset and record restart behavior before FreeRTOS hardware
   debugging.

Detailed commands and wiring are in
[`fpga/zynq_mini_revb/README.md`](../fpga/zynq_mini_revb/README.md).

## 2026-08-23 UART, FreeRTOS, and reset closure

**Problem/root cause:** Physical UART, production FreeRTOS, and repeated-reset
gates lacked external evidence. During observation, a few malformed UART bytes
and repeated banners could have indicated a baud/signal problem or spontaneous
reset. The user confirmed every repeated non-heartbeat banner followed a
deliberate K2 press; readable output was otherwise sustained, so the malformed
fragments are consistent with manual reset interrupting an in-flight UART
character rather than a persistent baud mismatch.

**Options considered:** Treat any malformed reset-boundary byte as a failed
115200 path; require an ILA before accepting external behavior; or separate
steady-state UART correctness from characters deliberately interrupted by
reset. The last option was selected because clean exact messages, sustained
heartbeats, D1 activity, and repeatable restart behavior directly exercise the
milestone outputs. ILA remains available if later failures require internal
visibility.

**Decision/consequences/evidence:** Close physical `hello`, production
FreeRTOS UART/GPIO, and repeated K2 reset observation. Preserve rather than
suppress `REQP-1839`, keep the unknown speed grade open, and avoid claiming a
physical UART RX stress test. The retained 7,330-byte PuTTY log has SHA-256
`620050E9D6515419BEEF0B2ED5F1B7336DA4A5F120BE62C998DBCE7700A3DC2B` and
contains 74 exact hello strings, 17 deliberate-reset FreeRTOS banners, and 537
exact heartbeats. Screenshots, hashes, setup, limitations, and observations are
recorded in
[`evidence/board_20260823/README.md`](evidence/board_20260823/README.md).
