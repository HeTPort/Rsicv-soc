# `p0_freertos` Power Workload Design

## Status and identity

Version `1.0`; lifecycle `verified`: functional tests, exact 95 MHz route,
reviewed activity mapping, and two-run repeatability pass. The distinct
`freertos_demo_p0` image is built
from the existing demo plus the unchanged, separately licensed FreeRTOS kernel.
The production `freertos_demo` image remains free-running and unmarked.

## Purpose

Measure a steady, preemptive operating-system workload with timer ticks,
ordered queue handoffs, context switches, polling UART TX, GPIO updates,
instruction/data BRAM, and the SoC fabric. This complements the bare-metal
compute, WFI, and RAM-stream scenarios rather than replacing them.

## Design intent

Four tasks run under the official FreeRTOS RV32 port: a queue producer,
highest-priority ordered receiver, heartbeat UART writer, and GPIO LED task.
The queue send path retains its `s2`–`s11` context sentinel. The P0-only
profile sets `configCPU_CLOCK_HZ=95,000,000`, `configTICK_RATE_HZ=1,000`,
`TIMER_TICK_CYCLES=1`, and the demonstration delay scale to 100. Thus the
kernel's tick interval is 95,000 actual 95 MHz core cycles; the producer,
LED, and heartbeat task delays are 1, 5, and 10 ticks respectively. This
accelerated task-period mix preserves their original 1:5:10 ratio but is
**not** the production 25 MHz/real-time task-rate image.

## Non-goals

- No idle-only or WFI-sleep claim; the FreeRTOS idle task spins.
- No physical board-rail, ASIC, or application-specific real-time workload
  accuracy claim.
- No UVM dependency, new MMIO register, kernel source copy, or production
  firmware behavior change.

## Fixed inputs and useful work

The queue producer sends monotonically increasing words. The receiver rejects
an out-of-order value, and the context sentinel checks preserved registers.
After 12 correct queue receives (warmup), START is committed to the ELF-
resolved `p0_freertos_marker`. Exactly 16 more correct receives lead to END.
One useful-work unit is one ordered queue receive in this measured interval.
The image uses fixed task priorities, four-deep queue, stack sizes, 115200 8N1
UART, and GPIO toggle pattern.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Warmup / START | Scheduler running; 12 ordered queue receives, then committed START marker `0x504F5752`. |
| END | Receiver reaches exactly 28 ordered receives and commits END marker `0x454E4421`. |
| Final PASS | Interrupts disabled after END; at least 16 tick hooks, two LED updates, and one completed heartbeat occurred in-window; committed `tohost=1`. |

Distinct failure codes cover queue order, context, allocation, trap, and P0
window counters. `tb_power` independently rejects missing, duplicate, or
misordered markers and `tohost` without the complete window. The separate SoC
regression independently decodes UART, GPIO, and timer-interrupt activity.

## Expected block activity

| Block | Expected behavior |
|---|---|
| CPU pipeline and BRAM | Continuous scheduler/task execution, bursts of context save/restore. |
| Timer and CSR/trap path | 1 kHz-equivalent tick interrupt at the declared 95 MHz core clock. |
| LSU/fabric/data BRAM | Task stacks, queue data, UART/GPIO/timer MMIO. |
| UART TX and GPIO | Heartbeat strings and LED toggles in the capture interval. |
| Divider | No architectural DIV/REM; should be inactive. |
| Combinational DSP multiplier | May switch incidentally; measure rather than force idle. |

## Functional oracle and failure consequences

Firmware PASS requires exact ordered queue traffic through receive 28,
context-sentinel preservation, and minimum in-window tick/LED/heartbeat
counts, followed by `tohost=1`. The SoC functional test additionally requires
the FreeRTOS UART byte pattern, GPIO sequence, and at least 24 timer IRQs.
Any failure code, timeout, missing marker, unexpected trap, or decoded I/O
mismatch rejects the workload before power analysis.

## Key performance indicators

| KPI ID | Metric | Unit | Acceptance/comparison rule | Evidence |
|---|---|---|---|---|
| P0RTOS-KPI-001 | Functional oracle | pass/fail | Firmware and independent SoC/power-TB checks PASS | PASS |
| P0RTOS-KPI-002 | Ordered queue receives | receives | Exactly 16 in-window | PASS |
| P0RTOS-KPI-003 | Tick hooks | ticks | At least 16 in-window; report exact | PASS, 18 |
| P0RTOS-KPI-004 | LED and heartbeat work | events | At least two LED updates and one heartbeat in-window | PASS, 4 LED and 2 heartbeat |
| P0RTOS-KPI-005 | Cycles per queue receive | cycles/receive | Report marker-window cycles / 16 | 106,813.9375 |
| P0RTOS-KPI-006 | Dynamic energy per receive | J/receive | Activity W × window seconds / 16 | 1.34923e-4 |
| P0RTOS-KPI-007 | Routed timing/DRC | ns/count | WNS >= 0, TNS 0, blocking DRC 0 | PASS, +0.003 ns / 0 / 0 blocking |
| P0RTOS-KPI-008 | Activity mapping | pass/fail | >=80% direct or reviewed block-level alternative | PASS via 13/13 reviewed rules; direct 483/8,762 |
| P0RTOS-KPI-009 | Dynamic repeatability | percent | <=2% across two independent captures | PASS, 0.0% |

## Reproducibility identity

Retain the exact `_p0` compiler flags, ELF/image hashes, symbol address,
source/upstream FreeRTOS revision and license, 95 MHz routed checkpoint hash,
part/constraints, `TIMER_TICK_CYCLES=1`, UART baud, task delay scale, marker
and work counts, testbench hierarchy, SAIF/VCD hashes, block coverage, power
report decomposition, and two-run comparison. Changing any of these creates
a different scenario identity.

## Risks and limitations

The SoC regression testbench runs at a separate functional clock/fast UART;
its scoreboard proves behavior but is not the activity source. `tb_power` at
95 MHz supplies the measurement identity, and its SAIF must map to the exact
95 MHz board route. The task delay scale is accelerated relative to the
production image. The UART polling interval may dominate portions of the
window. Functional RTL SAIF omits routed glitches; low direct-name mapping
requires a reviewed block-level alternative.

## Verification and evidence

The `_p0` image builds, and both functional SoC and power-TB regressions pass.
The SoC scoreboard saw 28 timer IRQs, 39 decoded UART bytes, and six GPIO
transitions. The power testbench captured START cycle 1,452,584 and END cycle
3,161,607, or 1,709,023 cycles and 433,663 retired instructions. It observed
18 tick hooks, four LED updates, and two completed heartbeats from committed
post-window result stores. The matching 95 MHz route passes at WNS +0.003 ns,
TNS 0, with zero blocking DRC. SAIF imports, all 13 reviewed block rules,
and 0.0% two-run dynamic repeatability pass. Full commands, hashes, report
categories, and limitations are in [measured results](results.md). Direct-name
mapping remains 5.5%, not 80%.
