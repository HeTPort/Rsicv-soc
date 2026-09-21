# `p0_wfi_timer` Measured Results

Status: **VERIFIED workload**, not physical power sign-off. Evidence date:
2026-09-19. The other scenario classes were subsequently verified on
2026-09-20; see the [P0 portfolio verdict](../../../doc/plans/p0-power-baseline/results.md).

## Functional and capture identity

- Original firmware: `sw/apps/p0_wfi_timer/main.c` and `trap.S`; 64 validated
  timer interrupts at 4,096 `mtime` ticks per scheduled wake.
- Marker symbol: `p0_wfi_timer_marker = 0x80000004`; START `0x504F5752`, END
  `0x454E4421`, then committed `tohost = 1`.
- SoC regression and `tb_power` regression: PASS. Both retained SAIF runs:
  START cycle 155, END cycle 275,055, 274,900 window cycles, 6,867 retired
  instructions, exact 64-wake functional oracle.
- Clock: 95 MHz; `TIMER_TICK_CYCLES=1` in both simulation and board route.
  The first route with tick period 3 was rejected and rebuilt before analysis.
- Work metrics: 4,295.3125 cycles/wake, 107.296875 instructions/wake.
- Optional `debug_vcd1` produced a 28,722,318-byte marker-window VCD under
  `tb_power/u_soc`; routine repeatability runs omit it to bound storage.

## Routed target

- Vivado 2019.2, provisional `xc7z010clg400-1`, exact 95 MHz MMCM profile.
- Matching checkpoint: `build/zynq_mini_revb/p0_wfi_timer_95mhz/top_routed.dcp`,
  SHA-256 `DB2554595B18D910433BD0DC8C2A3BAC9EB18795F7615DD3F7ED5CDFEEE37B64`.
- Routed setup WNS +0.003 ns, TNS 0.000 ns; constraints met. DRC has zero
  Error/Critical Warning and 38 advisory warnings, including the existing
  asynchronous-control-to-BRAM warning. Program/data RAM infer 16 RAMB36
  blocks each.

## Mapping and power gate

The RTL SAIF directly matches 483/8,762 routed logical nets (5.5124%), not
80%. Packed-struct renaming and combinational absorption prevent a raw-name
coverage claim. The reviewed REQ-P0-004 alternative passes all 13 rules in
`mapping_coverage.json`: directly observed CPU, LSU/fabric, BRAM interfaces,
timer bus interface, clock, divider and idle UART/GPIO boundaries; all 128
routed timer register Q nets receive measured per-bit `mtime`/`mtimecmp`
activity (81 active); routed DSP operands/results receive the measured low
incidental switching from the WFI workload. No MUL/DIV instruction executes,
but the combinational multiplier is not assumed power-gated.

| Metric | Vectorless | Reviewed activity run1 | Reviewed activity run2 |
|---|---:|---:|---:|
| Total on-chip estimate | 0.212 W | 0.209 W | 0.209 W |
| Dynamic estimate | 0.119 W | 0.117 W | 0.117 W |
| Device static estimate | 0.093 W | 0.093 W | 0.093 W |
| Confidence reported by Vivado | Medium | Medium | Medium |

The two activity-based dynamic estimates differ by 0.0%, passing the <=2%
gate. Dynamic energy per wake, including the fixed WFI interval, is
`0.117 W * (274900 / 95e6 s) / 64 = 5.2900e-6 J/wake`.

## Reproduction commands

```powershell
Set-Location sim/regress
.\run_regression.ps1 -Manifest .\power_tests.json -Test p0_wfi_timer
.\run_regression.ps1 -Manifest .\power_tests.json -Test p0_wfi_timer_power_tb
Set-Location ../..
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_wfi_timer -RunId run1
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_wfi_timer -RunId run2
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_wfi_timer -RunId debug_vcd1 -DumpVcd
$env:ZYNQ_MINI_CORE_CLOCK_HZ = '95000000'
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source .\fpga\zynq_mini_revb\build.tcl -tclargs p0_wfi_timer
Remove-Item Env:\ZYNQ_MINI_CORE_CLOCK_HZ
```

For each retained run, generate both bridges, apply SAIF plus bridges with
`power/scripts/analyze_vivado_power.tcl`, check
`power/workloads/p0_wfi_timer/mapping_coverage.json` with
`power/scripts/check_block_coverage.py --timer-bridge-json`, then call
`summarize_power_run.py --vivado-subdir vivado_reviewed
--reviewed-alternative <block_coverage.json>`. Compare the two summaries with
`compare_power_runs.py`; their generated artifacts remain ignored under
`build/power/p0_wfi_timer/`.

## Retained hashes

| Artifact | SHA-256 |
|---|---|
| `main.c` | `DB14FF2F4E5B65B5A931E826E16284C8C9BD8B6E8B78AAD8965A32E7397EC4D6` |
| `trap.S` | `180160B5173A7DADC388835251483353B7D2BCDB4D8D597891A98666A75B94E5` |
| ELF | `14045B45761303B2AE8B148EB318F3D07940EF50AEB41A3555D46569C3537D0C` |
| Program image | `3B4E3E7DF4B4C9339DE17CD616C078D7F0C01C913D2B6B3B094B1D45578909FC` |
| Data image | `A96F91E65AE6AFE90F8FEDD3FC63C48B8CA2E9E4FD5EC7AABBB88691A2571C89` |
| Routed checkpoint | `DB2554595B18D910433BD0DC8C2A3BAC9EB18795F7615DD3F7ED5CDFEEE37B64` |
| Routed timing summary | `16705528DF48DF97E46C1C4121BAC675C336D913E16DE5775D0D2B883F771128` |
| Routed DRC report | `36E3060ECBEF912FAEB62110827C1379A8C726FEBD3ADAEA5988D56DE2E08A18` |
| Run1 SAIF | `FC0A02B68EC36CB1D90A60026BE0C5EE8EDE15070AC9C7F35BE3A44DB8F4CD55` |
| Run2 SAIF | `965C78B17B7BA4267877BB7766CB72C933FF5AE10F5EB84428828B4E64700293` |
| Debug VCD | `89460B13DCC1C7E3A0EE56E933EFF6D3B0B2BD99F89E1623214CDCA0D377865C` |

Raw SAIF hashes differ in the generated DATE header; the two extracted
activity metrics and power estimates match. The reviewed estimate still uses
probabilistic propagation for optimized combinational nets, RTL activity
omits routed glitches, the PS7 power-property warning remains, and this is
not a board-rail or ASIC power measurement.
