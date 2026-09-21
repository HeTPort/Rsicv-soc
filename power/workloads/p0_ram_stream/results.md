# `p0_ram_stream` Measured Results

Status: **VERIFIED workload**, not physical power sign-off. Evidence date:
2026-09-19. The remaining scenario classes were subsequently verified on
2026-09-20; see the [P0 portfolio verdict](../../../doc/plans/p0-power-baseline/results.md).

## Functional and capture identity

- Original firmware: `sw/apps/p0_ram_stream/main.c`; independent
  `reference_model.py` yields checksum `0x58873A00` and final salt
  `0xC6EF3720`.
- Fixed stream: 32 passes × 256 words, one volatile source `lw` and one
  destination `sw` per inner iteration; 65,536 logical transfer bytes
  (64 KiB), not a pin-level counter. Disassembly places the only MUL in
  pre-START initialization, outside the measured kernel.
- ELF marker symbol/address: `p0_ram_stream_marker = 0x80000008`; START
  `0x504F5752`, END `0x454E4421`, then independent checksum, final-array,
  canary and committed `tohost=1` checks.
- SoC and power-TB functional regressions: PASS. Two independent SAIF runs:
  START cycle 11,939; END cycle 225,084; window 213,145 cycles; 98,414
  retired instructions. The two extracted work/activity metrics are identical.
- Throughput: `65536/213145 = 0.30747144` logical bytes/cycle, or
  3,330.390625 cycles/KiB. This includes loop, LSU, fabric, and BRAM latency.

## Exact routed target and mapping

- Vivado 2019.2, provisional `xc7z010clg400-1`, exact 95 MHz MMCM profile,
  `TIMER_TICK_CYCLES=1` in simulation and route.
- Checkpoint: `build/zynq_mini_revb/p0_ram_stream_95mhz/top_routed.dcp`,
  SHA-256 `0D99D9892D611C968455FC14830DF0C1424ADFCF9C47BC293D6F6D3216765280`.
- Routed WNS +0.003 ns, TNS 0.000 ns; zero Error/Critical Warning DRC and
  38 advisory warnings including the existing `REQP-1839` BRAM reset issue.
  There are 16 program and 16 data RAMB36 blocks.
- Direct RTL-SAIF name mapping is 483/8,762 routed logical nets (5.5124%),
  **not** an 80% direct mapping pass. The reviewed REQ-P0-004 alternative
  passes all 10 block rules in `mapping_coverage.json`: clock, active
  CPU/LSU/fabric and both BRAM boundaries, inactive divider/timer bus/UART/
  GPIO boundaries, and measured incidental combinational DSP activity mapped
  to routed nets. The fixed policy initially requested 12 directly active
  LSU/fabric nets; the first run observed 11/33, including
  `cpu_data_rsp_valid`. After reviewing these actual paths, the minimum was
  set to 10 distinct active nets and both runs passed 11/33. The DSP bridge
  records 1,854,001 SAIF transitions across 66 RTL `product_ext` bits;
  although no MUL retires in-window, the combinational multiplier cone is
  not power-gated and must not be forced idle.

## Power and normalization

| Metric | Vectorless | Reviewed activity run1 | Reviewed activity run2 |
|---|---:|---:|---:|
| Total on-chip estimate | 0.212 W | 0.222 W | 0.222 W |
| Dynamic estimate | 0.119 W | 0.129 W | 0.129 W |
| Device static estimate | 0.093 W | 0.093 W | 0.093 W |
| Vivado confidence | Medium | Medium | Medium |

Two-run dynamic-power variance is 0.0% (threshold <=2%). Scenario-level
dynamic energy per transferred KiB, including CPU and board-clock overhead,
is `0.129 W * (213145 / 95e6 s) / 64 = 4.52232e-6 J/KiB`.
The activity report attributes 0.103 W to the MMCM, 0.011 W to clocks,
0.008 W to signals, 0.005 W to slice logic, 0.002 W to Block RAM, and
0.001 W to DSPs (rounded). This is not an isolated BRAM joule/byte figure;
it is a whole-PL scenario estimate normalized by logical work.

## Reproduction

```powershell
python .\power\workloads\p0_ram_stream\reference_model.py
wsl.exe -e bash -lc "cd /mnt/d/Rsicv-soc-worktrees/phase2-act4-cleanup && bash sw/build_firmware_wsl.sh --install p0_ram_stream"
Set-Location sim/regress
.\run_regression.ps1 -Manifest .\power_tests.json -Test p0_ram_stream
.\run_regression.ps1 -Manifest .\power_tests.json -Test p0_ram_stream_power_tb
Set-Location ../..
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_ram_stream -RunId run1
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_ram_stream -RunId run2
$env:ZYNQ_MINI_CORE_CLOCK_HZ = '95000000'
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source .\fpga\zynq_mini_revb\build.tcl -tclargs p0_ram_stream
Remove-Item Env:\ZYNQ_MINI_CORE_CLOCK_HZ
```

For each run, use `make_saif_dsp_bridge.py` on its SAIF; apply that bridge
with `analyze_vivado_power.tcl` to the exact checkpoint and `tb_power` strip
path; check `mapping_coverage.json` with `check_block_coverage.py`; and call
`summarize_power_run.py --vivado-subdir vivado_reviewed
--reviewed-alternative <block_coverage.json>`. Finally compare the two run
directories with `compare_power_runs.py`. Generated inputs/reports are under
ignored `build/power/p0_ram_stream/`.

## Retained SHA-256

| Artifact | SHA-256 |
|---|---|
| `main.c` | `D80AD0C1A689CBD465DBFBC5C1CBE90371C51F6C71F08B8EAC30E5A3EB6655F9` |
| Independent reference model | `C795EB21319A5969555C5163D1CFD60BC3D6C77944AF5DCCE27AA6D7CC6C0723` |
| ELF | `004298BE68268CFBB47BA061B634EA1A96A21E59CDA7244233B6CE2653CBC111` |
| Program image | `AF71726E73E6FB0056325379740C7F956C2182E291EFED6F92A5B2AF896B196B` |
| Data image | `12C4197999F62E7C59F3295F61860BE4B6367BC1EFB244B936F949B1F31AF325` |
| Routed checkpoint | `0D99D9892D611C968455FC14830DF0C1424ADFCF9C47BC293D6F6D3216765280` |
| Routed timing summary | `087BC94258F6141433B129B8E4933CE9731AEAB080C45DAA4279B01806C0898B` |
| Routed DRC report | `FCA4B42E530B9F7262CDE6CEFEED3F8850DE6924B9637594335F684DFCF3FD86` |
| Run1 SAIF | `6BF848D04B75DE08722DF391B16C12901C92A6C5A53F4A755FA53973D3DDEB8B` |
| Run2 SAIF | `AA6CF6ACA08A1495F1D2FF3EFD64779A950A8087504CF2162BC91CD62C67C75C` |

The raw SAIF hashes differ because the generated DATE header differs. RTL
functional SAIF omits routed glitches; unmatched optimized combinational
logic still receives probabilistic propagation. The PS7 power-property
warning and provisional part speed grade remain. No board-rail, silicon, or
ASIC power measurement is claimed.
