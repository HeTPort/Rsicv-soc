# RV32IM RISC-V SoC

A small 32-bit RISC-V processor and SoC written in SystemVerilog as a learning
project. The immediate goal is a transparent, testable path from instruction
fetch to bare-metal UART interaction and eventually preemptive FreeRTOS on an
FPGA—not maximum performance or Linux compatibility.

> I want to understand why every instruction retires exactly once, even when
> memory stalls, a branch redirects the pipeline, or a trap interrupts the
> normal path.

The repository records the reasoning as well as the RTL. Focused `AR*.md`
reports preserve failures, alternatives, decisions, consequences, and proof;
the [project knowledge base](doc/PROJECT_KNOWLEDGE_BASE.md) is the best gradual
introduction.

## Current development status

Phases 1–4 are complete. Phase 5 now provides a split-image C runtime, minimal
drivers, and three bare-metal programs verified in ModelSim and Vivado
out-of-context synthesis. Physical-board validation remains open.

| Area | Implemented now |
|---|---|
| ISA | RV32I plus RV32M; iterative 32-cycle DIV/DIVU/REM/REMU |
| Pipeline | In-order packed packets, RAW stalls, redirects, delayed fetch kill, and canonical bubbles |
| Retirement | Central architectural decision point for RF/CSR writes, traps, MRET, WFI, and `minstret` |
| Privilege | Machine CSRs, legality/WARL behavior, precise synchronous exceptions and timer interrupts |
| WFI | Retires once, then enters a logical wait state until an eligible interrupt |
| Memory | Synchronous program/data RAM, one-outstanding LSU, byte lanes, alignment, wait states, and access faults |
| Fabric | Registered response-owner mux for timer, UART, GPIO, RAM, and default error target |
| Timer | 64-bit `mtime`/`mtimecmp`, MTIP level, local offsets `0xBFF8`/`0x4000` |
| UART | Polling 8N1 TX and RX, default 16-byte RX FIFO, sticky overrun/framing errors |
| GPIO | 32-bit R/W MMIO register driving parameterized low output bits; default width 8 |
| Verification | Focused protocol tests, 22/22 smoke, 47/47 applicable ACT4 I/M, Phase 3 2/2, Phase 4 3/3, Phase 5 4/4 |
| FPGA | Both ELF-derived images produce nonzero INIT in 16 program + 16 data RAMB36E1 cells; board constraints/hardware remain open |
| Software | Reset-to-C runtime, split linker, UART/GPIO/timer/CSR drivers, and three bare-metal apps; FreeRTOS remains open |

This is a verified development baseline, not a complete ISA-compliance or
production-readiness claim. There is no cache, MMU, S-mode, PLIC, AXI fabric,
or full forwarding network.

## Architecture at a glance

```mermaid
flowchart LR
  PRAM["Synchronous program RAM"] --> IF["IF / IF-ID"]
  IF --> ID["ID / ID-EX"] --> EX["EX + iterative divider"]
  EX --> LSU["LSU: one outstanding request"] --> FABRIC["SoC data fabric"]
  FABRIC --> TIMER["mtime / mtimecmp"]
  FABRIC --> UART["UART MMIO"]
  FABRIC --> GPIO["GPIO_OUT MMIO"] --> GPIOPIN["gpio_out_o"]
  FABRIC --> DRAM["Synchronous data RAM"]
  FABRIC --> ERR["Default error target"]
  LSU --> RETIRE["EX-WB / retire_stage"]
  RETIRE --> RF["Register file"]
  RETIRE --> CSR["CSR state / trap entry"]
  UART --> TX["TX holding byte + shifter"] --> TXPIN["uart_tx_o"]
  RXPIN["uart_rx_i"] --> RX["2-flop sync + RX sampler"] --> FIFO["RX FIFO, default 16"] --> UART
```

Instruction RAM has one-cycle read latency, so fetch carries a delayed request
PC beside each response and kills the stale response after a redirect. The LSU
captures a memory request, holds its payload stable until accepted, waits for
exactly one response, and advances the owning instruction only after completion.

`retire_stage.sv` is the architectural boundary. Execution may produce a
redirect or trap candidate, but only retirement chooses register/CSR effects,
trap entry, MRET, WFI entry, and the next architectural PC. This distinction
keeps younger or faulting instructions from leaking side effects.

The data fabric decodes full addresses, subtracts each target base, and records
which target accepted the request. The registered owner—not the current
address—selects the later response. That is essential when RAM or a peripheral
responds after the request cycle.

## UART: the current FPGA interaction path

The UART uses the native `core_bus_req_t`/`core_bus_rsp_t` protocol; there is no
APB bridge and no packet/CRC layer.

| Address | Register | Access | Meaning |
|---:|---|---|---|
| `0x1000_0000` | `TXDATA` | W | Enqueue low byte for transmission |
| `0x1000_0004` | `STATUS` | R | TX ready/busy, RX valid/full/errors/count |
| `0x1000_0008` | `RXDATA` | R | Pop oldest received byte; zero when empty |
| `0x1000_000C` | `RXERROR` | R/W1C | Sticky overrun and framing-error flags |

`STATUS[0]` is TX ready, `[1]` TX busy, `[2]` RX valid, `[3]` RX full,
`[4]` RX overrun, `[5]` RX framing error, and `[15:8]` RX count.

The RX pin first passes through a two-flop synchronizer. A separate midpoint
8N1 sampler emits byte or framing-error events; the MMIO target then owns FIFO
and sticky-error policy. If the FIFO is full, the newest byte is dropped and
old ordered data is preserved. An empty RXDATA read returns immediately rather
than deadlocking the core bus.

See the [Phase 4 UART guide](docs/phase4-uart-guide.md),
[AR-020 TX](doc/AR020_MINIMAL_POLLING_UART_TX.md), and
[AR-021 RX FIFO](doc/AR021_POLLING_UART_RX_FIFO.md).

## GPIO: the current LED/output path

`GPIO_OUT` is a 32-bit R/W register at `0x1000_1000`. Its low
`GPIO_WIDTH` bits drive `gpio_out_o`; the default width is eight and the
default reset value is zero. Legal byte, aligned halfword, and aligned word
writes merge only their selected lanes. Invalid offsets, alignment, or strobes
return a registered error and cannot change the output.

See the [Phase 4 GPIO guide](docs/phase4-gpio-guide.md) and
[AR-022](doc/AR022_MEMORY_MAPPED_GPIO_OUTPUT.md).

## Verification evidence

Tests report completion through a committed store to `tohost`: value 1 is
PASS; another nonzero value is a test-specific failure. The regression runner
also requires simulator exit zero, the architectural PASS marker, no fatal
marker, and zero ModelSim errors, preventing PASS-looking false positives.

| Gate | Current result | What it proves |
|---|---:|---|
| Smoke regression | 22/22 PASS | Directed CPU, CSR, trap, LSU, and bus behavior |
| Applicable ACT4 | 47/47 PASS | 39 RV32I and 8 RV32M architectural cases |
| Phase 3 | 2/2 PASS | Precise timer/WFI behavior and long-duration timer run |
| Phase 4 | 3/3 PASS | UART text, 16-byte RX-to-TX echo, and GPIO pin waveform/readback |
| Phase 5 | 4/4 PASS | Split data image, C startup/UART, timer-polled GPIO, and ten full-context timer interrupts |
| SoC-map generator unit tests | 9/9 PASS | Canonical map validation and generated addresses |
| UART focused tests | PASS | TX/RX framing, FIFO order/full/error/W1C, and bus semantics |
| Vivado 2019.2 OOC SoC check | PASS | 0 errors/critical warnings; BRAM, LSU, UART RX/TX, and GPIO hierarchy retained |

The Phase 4 echo test drives actual 8N1 waveforms into `uart_rx_i`. Firmware
polls and drains a 16-byte stream, writes each byte to TX, and an independent
serial decoder checks `RX FIFO 16 OK!\r\n`. The focused FIFO test separately
fills all 16 entries and verifies full/overrun behavior. Together they verify
the complete pin → receiver → FIFO → CPU → transmitter → pin path in simulation.

## Try it

### Requirements

- ModelSim or QuestaSim (`vlog` and `vsim` on `PATH`)
- Windows PowerShell for the regression scripts
- Python 3 for map/tool tests
- a RISC-V GNU toolchain under WSL when rebuilding assembly images
- Vivado 2019.2 or compatible for optional synthesis checks

### Main core simulation

```powershell
Set-Location .\sim
vsim -do run.do
```

### Focused peripheral and fabric tests

From `sim/`:

```powershell
vsim -c -do run_uart_tx.do
vsim -c -do run_uart_rx.do
vsim -c -do run_core_bus_uart.do
vsim -c -do run_core_bus_uart_rx.do
vsim -c -do run_core_bus_gpio.do
vsim -c -do run_soc_data_fabric.do
```

### Regressions

From `sim/regress/`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run_regression.ps1 -Tag smoke
.\run_regression.ps1 -Manifest .\phase3_tests.json
.\run_regression.ps1 -Manifest .\phase4_tests.json -Tag phase4
.\run_regression.ps1 -Manifest .\phase5_tests.json -Tag phase5
.\test_regression_result.ps1
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Useful selectors include `-List`, `-Test soc_uart_echo`, `-Tag lsu`, and
`-Trace -DumpWaves`. See the [regression guide](sim/regress/README.md).

### Generate and validate the SoC map

[`config/soc_map.json`](config/soc_map.json) is the single editable source for
RTL, firmware, linker, simulation, synthesis, and ACT4 address artifacts.

```powershell
python .\tools\gen_soc_map.py
python .\tools\gen_soc_map.py --check
python -m unittest tools/test_gen_soc_map.py
```

Do not hand-edit generated map files. An `accepted` map freezes the hardware/
software ABI; implementation status is recorded separately.

### Optional Vivado boundary checks

From `sim/synth/`:

```powershell
vivado -mode batch -source .\check_riscv_soc_ar003.tcl
vivado -mode batch -source .\check_riscv_soc_configured_ram.tcl
vivado -mode batch -source .\check_phase5_firmware_init.tcl
vivado -mode batch -source .\compare_riscv_soc_ram_utilization.tcl -tclargs ram_16k
vivado -mode batch -source .\compare_riscv_soc_ram_utilization.tcl -tclargs ram_64k
```

These are out-of-context checks using the provisional FPGA part. They prove
synthesizability and resource retention, not post-route timing or correct board
pins. Physical proof waits for a board-specific top and XDC.

## Repository map

```text
src/
  core/       CPU pipeline, packets, control, LSU, divider, retirement, CSRs
  bus/        RAM adapter, SoC fabric, and default error target
  generated/  Generated SoC-map SystemVerilog constants
  mem/        Synchronous program and data RAM
  periph/     Machine timer, UART MMIO/TX/RX, and GPIO MMIO
  riscv_soc.sv

sim/
  tb/         Core, SoC, protocol, timer, and UART testbenches
  regress/    Manifests, runner, image tools, and ACT4 adapters
  synth/      Vivado out-of-context checks
  generated/  Generated normalized map/Tcl data

config/       Authoritative SoC map and generator contract
firmware/     Generated C/linker map consumers
sw/           Reset runtime, linker, minimal drivers, and bare-metal apps
testdata/     Directed assembly and readmemh images
tools/        Map generator and dependency-free tests
verif/act4/   RISC-V Architecture Test integration
doc/          Living architecture documents and focused AR reports
docs/         Phase-oriented implementation guides
```

Build scripts list sources explicitly. Planned modules are added only when a
phase defines a real interface; empty future placeholders are not kept.

## Roadmap and open gates

The next practical steps are:

1. record the exact board, part/package/speed grade, clock/reset, UART/LED pins,
   schematic, and vendor XDC;
2. add a board-specific top, reset/clock conditioning, constraints, and
   non-interactive implementation/bitstream flow;
3. run the same three Phase 5 images on the FPGA;
4. integrate the official FreeRTOS RISC-V port and validate context switching;
5. close post-route timing and test the FreeRTOS demonstration on the FPGA;
6. add UART interrupts/PLIC only after the polling baseline is stable on
   hardware.

You do not need to connect the FPGA board to develop or verify the RTL. You do
need it to close the hardware gate: asynchronous input behavior, oscillator
accuracy, reset polarity, I/O voltage, physical pins, USB-UART crossover, and
post-route timing cannot be proven by RTL simulation.

[`TODO.md`](TODO.md) is the authoritative checklist. Design semantics and
naming standards are in
[`doc/SEMANTIC_SIGNAL_SPEC.md`](doc/SEMANTIC_SIGNAL_SPEC.md); accepted choices
and their history are in
[`doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md`](doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md).

## A personal note

This is a learning record, not a production-ready processor. Mature open-source
cores are far ahead in features, performance, and verification. The unfinished
parts are kept visible because they often contain the most useful lessons.

AI tools have helped with implementation and documentation, but generated code
or prose is not proof. A change is accepted only when its behavior is
understood, its failure mode is testable, and the focused and full regressions
remain green.
