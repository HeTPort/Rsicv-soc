# AR-015 RAM-Capacity Utilization and Timing Comparison

## Status

**Paired out-of-context utilization and post-synthesis static-timing
experiments completed and verified on 2026-08-01.**

**Historical RED baseline:** AR-017 subsequently replaced the timing-dominant
combinational divider and records the refreshed GREEN utilization/timing
comparison. The measurements below intentionally preserve the pre-fix design.

This evidence answers the narrow questions of how 16 KiB and 64 KiB
instruction/data RAM banks affect synthesized resources and whether RAM
capacity changes the current internal critical path. This experiment did not by
itself accept the AR-009 memory map, prove post-route timing closure, or reserve
resources for the future decoder, timer, UART, GPIO, and board wrapper. AR-009
was subsequently accepted using this evidence and the remaining contract
decisions.

## Question

The checked-in RTL defaults to 4096 32-bit words, or 16 KiB, in each RAM bank.
The accepted FreeRTOS map reserves 64 KiB per bank. Before changing the
implemented map, measure both capacities with the same RTL, tool, part, and
synthesis mode.

## Controlled experiment

| Variable | Value held constant |
|---|---|
| RTL top | `riscv_soc` |
| Vivado | 2019.2 |
| FPGA part | provisional `xc7z010clg400-1` |
| Synthesis mode | out of context |
| Address/data width | 32/32 |
| RAM implementation | existing `prog_ram` and `data_ram` BRAM templates |

Only `PROG_RAM_DEPTH` and `DATA_RAM_DEPTH` changed. The values were not copied
into the synthesis script: `config/soc_map.json` declares the candidate byte
sizes, `tools/gen_soc_map.py` derives word depths, and
`sim/generated/soc_ram_utilization_profiles.tcl` supplies the named profiles.

```text
config/soc_map.json
        |
        v
tools/gen_soc_map.py
        |
        v
sim/generated/soc_ram_utilization_profiles.tcl
        |
        v
compare_riscv_soc_ram_utilization.tcl
        |
        +-- ram_16k: 4096 words per bank
        +-- ram_64k: 16384 words per bank
```

Utilization commands:

```powershell
Set-Location D:\Rsicv-soc\sim\synth
New-Item -ItemType Directory -Force `
  ..\..\build\vivado_ram_16k, ..\..\build\vivado_ram_64k | Out-Null
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch `
  -log ..\..\build\vivado_ram_16k\vivado.log `
  -journal ..\..\build\vivado_ram_16k\vivado.jou `
  -source .\compare_riscv_soc_ram_utilization.tcl `
  -tclargs ram_16k
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch `
  -log ..\..\build\vivado_ram_64k\vivado.log `
  -journal ..\..\build\vivado_ram_64k\vivado.jou `
  -source .\compare_riscv_soc_ram_utilization.tcl `
  -tclargs ram_64k
```

## Results

| Resource | 16 KiB per bank | 64 KiB per bank | Delta |
|---|---:|---:|---:|
| Slice LUTs | 7,861 / 17,600 (44.66%) | 7,902 / 17,600 (44.90%) | +41 |
| Slice registers | 2,465 / 35,200 (7.00%) | 2,467 / 35,200 (7.01%) | +2 |
| Block RAM tiles / RAMB36E1 | 8 / 60 (13.33%) | 32 / 60 (53.33%) | +24 |
| DSPs | 12 / 80 (15.00%) | 12 / 80 (15.00%) | 0 |

The hierarchical reports attribute four RAMB36E1 cells to each 16 KiB bank
and sixteen to each 64 KiB bank. The fourfold capacity increase therefore
causes the expected fourfold BRAM increase; the non-memory resource difference
is small.

The 64 KiB pair fits this provisional part after synthesis and leaves 28 of 60
Block RAM tiles, or 46.67%, for later logic and memories. That remaining amount
is a planning observation, not a final resource margin.

## Post-synthesis static-timing experiment

The utilization flow writes one synthesized DCP per generated RAM profile.
`report_riscv_soc_ram_timing.tcl` reopens each DCP with a clean constraint set,
applies 50 MHz (20 ns) and 25 MHz (40 ns) clock targets, and reports only
internal register-to-register setup paths. This is static timing analysis, not
event-driven gate-level timing simulation.

```powershell
Set-Location D:\Rsicv-soc\sim\synth
New-Item -ItemType Directory -Force `
  ..\..\build\vivado_ram_16k\timing, `
  ..\..\build\vivado_ram_64k\timing | Out-Null
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch `
  -log ..\..\build\vivado_ram_16k\timing\vivado_timing.log `
  -journal ..\..\build\vivado_ram_16k\timing\vivado_timing.jou `
  -source .\report_riscv_soc_ram_timing.tcl `
  -tclargs ram_16k
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch `
  -log ..\..\build\vivado_ram_64k\timing\vivado_timing.log `
  -journal ..\..\build\vivado_ram_64k\timing\vivado_timing.jou `
  -source .\report_riscv_soc_ram_timing.tcl `
  -tclargs ram_64k
```

| Profile | Clock target | WNS | TNS | Failing setup endpoints | Worst data path |
|---|---:|---:|---:|---:|---:|
| 16 KiB/bank | 50 MHz | -67.124 ns | -2101.336 ns | 32 | 87.102 ns |
| 64 KiB/bank | 50 MHz | -67.124 ns | -2101.336 ns | 32 | 87.102 ns |
| 16 KiB/bank | 25 MHz | -47.124 ns | -1461.336 ns | 32 | 87.102 ns |
| 64 KiB/bank | 25 MHz | -47.124 ns | -1461.336 ns | 32 | 87.102 ns |

Both capacities produce the same worst path: 305 logic levels from the ID/EX
operand register to EX/WB ALU result bit 26 through
`u_execute/muldiv_result3`. The detailed path contains 291 CARRY4 levels and is
the combinational RV32M divide/remainder chain. It is not a program- or
data-RAM path. The reciprocal of 87.102 ns is about 11.48 MHz, but that is only
an idealized post-synthesis indication, not a routed Fmax.

The important result is therefore not that 64 KiB makes timing worse. RAM size
has no observed effect on the dominant path; the current combinational divider
fails both candidate 25 MHz and 50 MHz targets in both configurations.

## Preserved evidence

The concise metadata and both flat and hierarchical reports are retained here:

- [`ram_16k_experiment_metadata.txt`](evidence/ar015_ram_capacity/ram_16k_experiment_metadata.txt)
- [`ram_16k_riscv_soc_utilization.rpt`](evidence/ar015_ram_capacity/ram_16k_riscv_soc_utilization.rpt)
- [`ram_16k_riscv_soc_hierarchical_utilization.rpt`](evidence/ar015_ram_capacity/ram_16k_riscv_soc_hierarchical_utilization.rpt)
- [`ram_64k_experiment_metadata.txt`](evidence/ar015_ram_capacity/ram_64k_experiment_metadata.txt)
- [`ram_64k_riscv_soc_utilization.rpt`](evidence/ar015_ram_capacity/ram_64k_riscv_soc_utilization.rpt)
- [`ram_64k_riscv_soc_hierarchical_utilization.rpt`](evidence/ar015_ram_capacity/ram_64k_riscv_soc_hierarchical_utilization.rpt)

Timing metadata, summaries, and detailed worst-path reports are retained here:

- [`ram_16k_timing_metadata.txt`](evidence/ar015_ram_capacity/timing/ram_16k_timing_metadata.txt)
- [`ram_16k_riscv_soc_timing_summary_50mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_16k_riscv_soc_timing_summary_50mhz.rpt)
- [`ram_16k_riscv_soc_register_timing_50mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_16k_riscv_soc_register_timing_50mhz.rpt)
- [`ram_16k_riscv_soc_timing_summary_25mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_16k_riscv_soc_timing_summary_25mhz.rpt)
- [`ram_16k_riscv_soc_register_timing_25mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_16k_riscv_soc_register_timing_25mhz.rpt)
- [`ram_64k_timing_metadata.txt`](evidence/ar015_ram_capacity/timing/ram_64k_timing_metadata.txt)
- [`ram_64k_riscv_soc_timing_summary_50mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_64k_riscv_soc_timing_summary_50mhz.rpt)
- [`ram_64k_riscv_soc_register_timing_50mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_64k_riscv_soc_register_timing_50mhz.rpt)
- [`ram_64k_riscv_soc_timing_summary_25mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_64k_riscv_soc_timing_summary_25mhz.rpt)
- [`ram_64k_riscv_soc_register_timing_25mhz.rpt`](evidence/ar015_ram_capacity/timing/ram_64k_riscv_soc_register_timing_25mhz.rpt)

The larger checkpoints, journals, and complete logs remain ignored under
`build/vivado_ram_16k` and `build/vivado_ram_64k`.

## Interpretation and limits

- Both configurations retain instruction and data RAM as Block RAM.
- The 64 KiB configuration is synthesizable on the provisional part, but its
  two banks consume more than half of the available Block RAM tiles.
- The utilization synthesis had no clock constraint. The later timing
  experiment adds only an ideal 25/50 MHz clock for internal post-synthesis
  setup analysis.
- The OOC port has no board-level `HD.CLK_SRC`, so Vivado cannot estimate clock
  delay/skew. There are no board I/O delays, placement, routing, power, or
  physical-board results.
- `check_timing` reports zero unconstrained internal maximum-delay endpoints,
  but 67 input and 406 output ports have no I/O delay. That is intentional for
  this internal-path experiment and prevents treating it as interface closure.
- The current RTL does not yet include the accepted address decoder, default
  error target, timer, UART, GPIO, or final board wrapper. Their cost is absent.
- The exact board package and speed grade still require confirmation. Changing
  the part requires rerunning both profiles before using the numbers as a gate.
- Vivado emitted an environment-level local Tcl-store permission warning and
  fell back to its installation area. Both synthesis runs still completed with
  zero design critical warnings and zero errors.

## Decision consequence

AR-011's paired utilization and early critical-path checkpoints are now
complete. Based on this evidence, the project selected 64 KiB for each RAM bank
on 2026-08-01. This is an architectural capacity choice, not proof of current
RTL implementation or final board closure. AR-017 subsequently implemented and
verified a restoring Radix-2 divider. The refreshed paired STA passes 50 MHz
with WNS +7.373 ns and 25 MHz with WNS +27.373 ns; exact-board
placement/routing and timing closure remain open. AR-009 and the Phase 1 ABI
are accepted; decoder and consumer adoption remain Phase 2. See
[`AR017_RADIX2_ITERATIVE_DIVIDER.md`](AR017_RADIX2_ITERATIVE_DIVIDER.md).

## Reusable principle

Keep capacity selection separate from capacity implementation: derive named
experiment profiles from the same machine-readable source, change only the
elaboration parameters under test, preserve raw reports, and promote a size to
the architectural map only after resource, software, and timing gates agree.
