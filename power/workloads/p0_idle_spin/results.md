# `p0_idle_spin` Measured Results

Status: **VERIFIED clocked spin-idle reference**, not a WFI/deep-sleep or
physical power result. Evidence date: 2026-09-20.

## Functional and capture identity

- Original `sw/apps/p0_idle_spin/main.c`; fixed 65,536-iteration register-only
  `nop`/`addi`/`bnez` assembly loop. `p0_idle_spin_marker = 0x80000004`
  holds committed START `0x504F5752` and END `0x454E4421` values.
- Both SoC and power-TB functional tests PASS. Both independent SAIF windows
  contain 458,759 cycles and 196,611 retired instructions; a committed
  post-window result store is zero and `tohost=1`.
- The window has no intended data work. At most 0.000207087 MHz direct-S
  LSU/data-BRAM signal rates occur at the START-marker transaction tail;
  timer bus, UART, and GPIO direct boundaries remain inactive.
- Work metrics: 6.9999847 cycles and 3.0000458 retirements per spin
  iteration. Approximately `0.158 / 95e6 = 1.66316e-9 J` whole-PL dynamic
  energy per core cycle, or `1.16423e-8 J` per spin iteration.

## Routed target, mapping, and power

- Vivado 2019.2, provisional `xc7z010clg400-1`, exact 95 MHz route with
  `TIMER_TICK_CYCLES=1`; WNS +0.003 ns, TNS 0, zero Error/Critical Warning
  DRC. Program/data memories each infer 16 RAMB36 blocks.
- Direct RTL-SAIF mapping is **483/8,762 = 5.5124%**, not 80%. Both runs
  pass the 10-rule reviewed block alternative in `mapping_coverage.json`:
  measured clock/CPU/program-BRAM activity, bounded marker-tail LSU/data
  traffic, inactive timer/UART/GPIO/divider, and 281 measured-to-routed
  combinational DSP nets. The bridge's mean operand and product static
  probabilities needed recorded adjustments of only `2.218e-6` and
  `1.361e-6` to satisfy Vivado's toggle/probability bound. The unadjusted
  first import failed; `vivado_reviewed_corrected/` is the accepted import.
- A spinning CPU is not low power here. Changing loop operands drive the
  un-gated combinational multiplier (4,194,296 measured product-bit
  transitions), and repeated fetches raise program-BRAM activity. Do not
  substitute this value for WFI or a clock-gated idle state.

| Metric | Vectorless | Activity run1 | Activity run2 |
|---|---:|---:|---:|
| Total on-chip estimate | 0.212 W | 0.251 W | 0.251 W |
| Dynamic estimate | 0.119 W | 0.158 W | 0.158 W |
| Device static estimate | 0.093 W | 0.093 W | 0.093 W |
| Vivado confidence | Medium | Medium | Medium |

Two activity dynamic estimates differ by 0.0%, passing the <=2% gate. In the
activity report the MMCM contributes 0.103 W, clock networks 0.011 W, block
RAM 0.030 W, signals 0.008 W, slice logic 0.005 W, and DSP 0.001 W. These
are whole-PL report categories, not independently isolated core energy.

## Reproduction commands

```powershell
wsl bash sw/build_firmware_wsl.sh --install p0_idle_spin
.\sim\regress\run_regression.ps1 -Manifest .\sim\regress\power_tests.json -Test p0_idle_spin,p0_idle_spin_power_tb
$env:ZYNQ_MINI_CORE_CLOCK_HZ = '95000000'
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source .\fpga\zynq_mini_revb\build.tcl -tclargs p0_idle_spin
Remove-Item Env:\ZYNQ_MINI_CORE_CLOCK_HZ
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_idle_spin -RunId run1
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_idle_spin -RunId run2
```

Generate each run's reviewed DSP bridge with `make_saif_dsp_bridge.py`;
analyze the matching `p0_idle_spin_95mhz/top_routed.dcp` with
`analyze_vivado_power.tcl -tclargs <dcp> <saif> <output> tb_power <dsp>`.
For the retained runs, `<output>` is `vivado_reviewed_corrected` because the
initial unadjusted run1 bridge was rejected. Both `check_block_coverage.py`
and `summarize_power_run.py --vivado-subdir vivado_reviewed_corrected
--reviewed-alternative <block_coverage.json>` PASS;
`compare_power_runs.py` reports 0.0% dynamic variance. Large generated
artifacts remain ignored under `build/power/p0_idle_spin/`.

## Retained SHA-256 identities

| Artifact | SHA-256 |
|---|---|
| `main.c` | `356F505A5818B41A004DB9B5BC1AE7865DEC2C77962E3522F62112D4BAB28E7B` |
| ELF | `E863DB1977AB90F994C62A8B90488396E40A8DF214AD6190DCE3A004D6E5CB92` |
| Program image | `A3A4D42CBBEF3852816A4F17346EE7790C10B17D6AE5623FD86CDFFBD91D9D66` |
| Data image | `A96F91E65AE6AFE90F8FEDD3FC63C48B8CA2E9E4FD5EC7AABBB88691A2571C89` |
| Routed 95 MHz checkpoint | `C1B90D23D12F2AE3198669930E3A18AE6020E459790BE544386C644FF187E8BF` |
| Run1 / run2 SAIF | `BD948AD16042E95B6F855C2868FAFB814DBCFB8F4E01D84DC4037514BA1C61D7` / `BE8C6DA81C1D26A9AA3DF6277587B6780772F9641D375163E99C607C49F0444A` |
| Vectorless report | `ACF504D566DCD0E17E9EC6A0D2F0B09E751F6BA7D33285434D60746C188A1670` |
| Run1 / run2 activity report | `D1A4BCD9B749D617B6304E65E42F3A84CB3FAD961491E21B7C15B8E0175895EC` / `1496E961AE07F459BFF0FC9A12F76BD2D71D4BEFF4B826DC68074D09D95D3449` |

The SAIF hashes differ in generated DATE headers; the measured activity and
estimates agree. RTL functional SAIF omits routed glitches; unmatched nets
use probabilistic propagation. The PS7 property warning, provisional speed
grade, and absent board-rail measurement remain limitations.
