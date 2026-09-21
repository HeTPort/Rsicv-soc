# `p0_freertos` Measured Results

Status: **VERIFIED workload**, not physical power sign-off. Evidence date:
2026-09-20. The profile is a distinct `_p0` image; the production FreeRTOS
simulation image rebuilt byte-for-byte identical and its focused Phase 6
regression still passed.

## Functional and capture identity

- Existing official FreeRTOS V11.3.0 RISC-V port (MIT; upstream revision in
  `third_party/FreeRTOS-Kernel/UPSTREAM.md`) plus the P0-only conditional in
  `sw/apps/freertos_demo/main.c`. Four tasks exercise an ordered queue with
  register-context sentinel, timer ticks, UART heartbeat, and GPIO LED.
- `configCPU_CLOCK_HZ=95,000,000`, `configTICK_RATE_HZ=1,000`, task delay
  scale 100, `TIMER_TICK_CYCLES=1`, and UART 115200 8N1. This accelerated
  task-period profile is not the production 25 MHz/real-time image.
- Marker symbol `p0_freertos_marker = 0x800001F4`; START after 12 ordered
  receives and END after exactly 16 more. START/END words are `0x504F5752`
  and `0x454E4421`, followed by committed result stores and `tohost=1`.
- SoC regression PASS: 28 timer IRQs, 39 decoded UART bytes, and six GPIO
  transitions. Power TB PASS: 1,709,023 window cycles, 433,663 retired
  instructions, 18 in-window tick hooks, four LED updates, two completed
  heartbeats, and exact ordered queue progress. `run2` and `run3` are the
  independent accepted captures; exploratory `run1` predates result-store
  observation and does not count as a repeat.
- Work metrics: 106,813.9375 cycles and 27,103.9375 retired instructions per
  in-window receive. Whole-PL dynamic energy per receive is approximately
  `0.120 * (1709023 / 95e6) / 16 = 1.34923e-4 J`.

## Routed target, mapping, and power

- Vivado 2019.2, provisional `xc7z010clg400-1`, exact 95 MHz board route;
  WNS +0.003 ns, TNS 0, zero Error/Critical Warning DRC. Both program and
  data RAM infer 16 RAMB36 blocks. The routed checkpoint is workload-matched,
  not the production 25 MHz design.
- Direct RTL-SAIF mapping is **483/8,762 = 5.5124%**, not the 80% threshold.
  The documented REQ-P0-004 reviewed alternative passes all 13 rules in
  `mapping_coverage.json` on both runs: measured CPU/BRAM/LSU/fabric/timer
  interface/UART TX/GPIO switching, inactive architectural divider, 281
  bridged routed DSP nets, and all 128 bridged timer-Q nets (52 active).
- The UART RX is not stimulated. The combinational multiplier switches
  incidentally without architectural MUL/DIV; the bridge records that
  measured switching rather than assuming gating.

| Metric | Vectorless | Activity run2 | Activity run3 |
|---|---:|---:|---:|
| Total on-chip estimate | 0.212 W | 0.216 W | 0.216 W |
| Dynamic estimate | 0.119 W | 0.120 W | 0.120 W |
| Device static estimate | 0.093 W | 0.096 W | 0.096 W |
| Vivado confidence | Medium | Medium | Medium |

Both activity-based dynamic estimates agree to the report's 0.001 W
resolution: 0.0% difference, below the 2% gate. The activity report includes
0.103 W MMCM, 0.011 W clock networks, 0.004 W signals, 0.002 W slice logic,
and less than 0.001 W each for BRAM, DSP, and I/O. These are whole-PL
estimates, not independently attributable task/queue/UART energy.

## Reproduction commands

From the repository root, with the installed RISC-V toolchain, ModelSim SE
2019.2, and Vivado 2019.2:

```powershell
wsl env SOC_FREERTOS_MTIME_HZ=95000000 SOC_FREERTOS_DEMO_TIME_SCALE=100 SOC_FREERTOS_SIM_COMPLETION=0 SOC_FREERTOS_POWER_PROFILE=1 SOC_FREERTOS_IMAGE_SUFFIX=_p0 bash sw/build_firmware_wsl.sh --install freertos_demo
.\sim\regress\run_regression.ps1 -Manifest .\sim\regress\power_tests.json -Test p0_freertos,p0_freertos_power_tb
$env:ZYNQ_MINI_CORE_CLOCK_HZ = '95000000'
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source .\fpga\zynq_mini_revb\build.tcl -tclargs freertos_demo_p0
Remove-Item Env:\ZYNQ_MINI_CORE_CLOCK_HZ
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_freertos -RunId run2
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_freertos -RunId run3
```

For each accepted run, generate both bridges with
`make_saif_dsp_bridge.py` and `make_saif_timer_bridge.py`, apply SAIF and both
bridge Tcl files to the same `freertos_demo_p0_95mhz/top_routed.dcp` using
`analyze_vivado_power.tcl -tclargs <dcp> <saif> <output> tb_power <dsp> <timer>`,
then run `check_block_coverage.py` with this workload policy and
`--timer-bridge-json`. `summarize_power_run.py --vivado-subdir vivado_reviewed
--reviewed-alternative <block_coverage.json>` passes for both runs;
`compare_power_runs.py` reports PASS at 0.0%. Generated artifacts stay under
ignored `build/power/p0_freertos/`.

## Retained SHA-256 identities

| Artifact | SHA-256 |
|---|---|
| `sw/apps/freertos_demo/main.c` | `BD71087B1CBA124803AD9DAFF715697DF05E2B97DC03BD9B299CF1041044518B` |
| `_p0` ELF | `5392191069CE0B32616998D67489BAC04A745B7095CDAE4EC7D438AA85F9DA35` |
| `_p0` program image | `BB3FE59905AEFB15587CE8CCE2B7202E543D055409FB4B6956BA0B765B557457` |
| `_p0` data image | `ECA1CA29695ED175A1EEFBA9030C5E149AE56862B4207CCB424085F4C6BD7D60` |
| Routed 95 MHz checkpoint | `91F8CFE2A7F7A402D47F9129FAF89EE2452356C76519988CABDE7978319AD224` |
| Run2 / run3 SAIF | `79BA4EA1913FFBC0E55469513F0A60666F2EEEEF0118E8B4DB5272A9A8E85D23` / `9A85143452545B682259519F13F167494B11AA30E1ED873620397AFDAA2D3901` |
| Vectorless report | `F506D9EF0A8A0BB91AF072B01BE4E54006D4B3E8DBC952AE4CBB7FDD8F5228DC` |
| Run2 / run3 activity report | `DD53878065D7E6CEFD15A3F17EC25037C844EAE8C2F6AC5B35C5449BA4545428` / `5D42213D89BB2A231F02E3463A8542C76E9B0C4527810916E31B47BC68CB0702` |

The SAIF file hashes differ because their generated DATE headers differ;
their activity metrics and power estimates agree. RTL functional SAIF omits
routed glitches. Most optimized nets still use Vivado's probabilistic
propagation; the PS7 power-property warning and provisional speed grade
remain. This is not a board-rail, ASIC, or battery measurement.
