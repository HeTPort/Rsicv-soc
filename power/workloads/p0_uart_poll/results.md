# `p0_uart_poll` Measured Results

Status: **VERIFIED dedicated UART polling workload**, not physical power
sign-off. Evidence date: 2026-09-20.

## Functional and capture identity

- Original `sw/apps/p0_uart_poll/main.c` sends exactly 14 bytes,
  `Hello, UART!\r\n`, using the existing polling TX driver and waits for
  `TX_BUSY` to clear before END. `p0_uart_poll_marker = 0x80000014` holds
  committed START `0x504F5752` and END `0x454E4421`; result symbol
  `0x80000010` stores the exact 14-byte count after the window.
- The independent SoC testbench decodes all 14 serial bytes correctly.
  Both power-TB functional and independent SAIF runs PASS with 115,574
  window cycles, 31,540 retired instructions, result 14, and `tohost=1`.
- The routed and power-capture identity is 95 MHz, 115200 baud, 8N1,
  `TIMER_TICK_CYCLES=1`, and the split 64 KiB BRAM profile. The separate
  SoC functional decoder uses an accelerated UART clock only for validation;
  it is not the SAIF source.
- Work metrics: 8,255.2857 cycles and 2,252.8571 retired instructions
  per byte. Whole-PL dynamic energy is approximately
  `0.119 * (115574 / 95e6) / 14 = 1.03408e-5 J/byte`.

## Routed target, mapping, and power

- Vivado 2019.2, provisional `xc7z010clg400-1`, exact 95 MHz board route;
  WNS +0.003 ns, TNS 0, zero Error/Critical Warning DRC. Program/data RAM
  infer 16 RAMB36 blocks each.
- Direct RTL-SAIF mapping is **483/8,762 = 5.5124%**, not 80%. Both runs
  pass all 12 reviewed block rules in `mapping_coverage.json`: directly
  observed CPU, BRAM, LSU/fabric, UART holding-stage and TX serializer
  activity (20 active TX nets), idle UART RX/timer-bus/GPIO/divider, plus
  281 explicitly bridged routed DSP nets for incidental switching.
- No RX input, UART interrupt, DMA, or FreeRTOS task is part of this
  workload. The measured value includes CPU polling and clock distribution;
  it cannot be read as isolated UART-shifter power.

| Metric | Vectorless | Activity run1 | Activity run2 |
|---|---:|---:|---:|
| Total on-chip estimate | 0.212 W | 0.215 W | 0.215 W |
| Dynamic estimate | 0.119 W | 0.119 W | 0.119 W |
| Device static estimate | 0.093 W | 0.096 W | 0.096 W |
| Vivado confidence | Medium | Medium | Medium |

The two activity dynamic estimates differ by 0.0%, passing the <=2% gate.
At the report's 0.001 W resolution the vectorless and activity dynamic
totals coincide, even though the directly observed UART activity is nonzero.
The activity report includes 0.103 W MMCM, 0.011 W clock networks,
0.003 W signals, 0.002 W slice logic, and less than 0.001 W each for BRAM,
DSP, and I/O.

## Reproduction commands

```powershell
wsl bash sw/build_firmware_wsl.sh --install p0_uart_poll
.\sim\regress\run_regression.ps1 -Manifest .\sim\regress\power_tests.json -Test p0_uart_poll,p0_uart_poll_power_tb
$env:ZYNQ_MINI_CORE_CLOCK_HZ = '95000000'
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source .\fpga\zynq_mini_revb\build.tcl -tclargs p0_uart_poll
Remove-Item Env:\ZYNQ_MINI_CORE_CLOCK_HZ
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_uart_poll -RunId run1
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_uart_poll -RunId run2
```

Generate the per-run DSP bridge with `make_saif_dsp_bridge.py`, apply each
SAIF plus bridge to the matching `p0_uart_poll_95mhz/top_routed.dcp` using
`analyze_vivado_power.tcl -tclargs <dcp> <saif> <output> tb_power <dsp>`,
then run `check_block_coverage.py` with this policy and
`summarize_power_run.py --vivado-subdir vivado_reviewed
--reviewed-alternative <block_coverage.json>`. Both run gates PASS, and
`compare_power_runs.py` reports 0.0% dynamic variance. Generated artifacts
remain ignored under `build/power/p0_uart_poll/`.

## Retained SHA-256 identities

| Artifact | SHA-256 |
|---|---|
| `main.c` | `E8C45B1685E78787834000A25ED4AADF3100A1E235A6226C2601856C15D51DDC` |
| ELF | `4A088C07C31FDDA9D942B95AE08D09C38B27859C7ADAF7DB120776B20B28B2CD` |
| Program image | `8B8D80C50F5B55FD925233A01B3CBA64B5CD7D30107D88E31EE8D59E630A796C` |
| Data image | `3DC6213CBA70FD82C37943A2C9B6C9D7E047EB5F2EAC68CCFA9D6F7F29DDCC0C` |
| Routed 95 MHz checkpoint | `1048CC9E5EEF4E4FB136DFDDEAC235A97891D7C6B246E840AB05885BE9FBF100` |
| Run1 / run2 SAIF | `A4671D86B938A94992DCE8AFD6A6AFEEDEBD422672F32024CC178106A67499F0` / `83305330067E42A22233EF7F5CE1171340A31E136275771054CD1C503C0E9AA7` |
| Vectorless report | `DDF1649D57DEA97FC9F95B18EDAB0875BC2607A0B2F36B4DB99B2F237086FDBB` |
| Run1 / run2 activity report | `3515D55D6A9477E449AF2760D1304D5DC5645CC4470C9BAE93B7DF9348491C9F` / `B608EC79C314DA5286971BFD5132F1577C02256358F59BBCC832635BBEEFB7E2` |

SAIF DATE headers account for different raw hashes; extracted activity and
power metrics agree. RTL SAIF omits routed glitches, unmatched optimized
logic uses probabilistic propagation, the PS7 power-property warning remains,
and no board-rail or ASIC result is claimed.
