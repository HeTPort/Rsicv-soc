# `p0_mix` Evidence Record

## Functional prerequisite — 2026-09-16

This section records the functional prerequisite. The routed/activity evidence
that completes the workload follows it.

### Identity

- Git `HEAD`: `63b9cd3bc6e246056a50ff9eac2ddff832e88db5`
- Worktree: dirty; exact source/image hashes below define this run.
- Compiler: `riscv64-unknown-elf-gcc (14.2.0+19) 14.2.0`
- Linker: `GNU ld 2.45.50.20251209`
- Simulator: ModelSim SE-64 2019.2
- Firmware options: repository `sw/build_firmware_wsl.sh` defaults for RV32IM
  with Zicsr, ILP32, and optimization enabled.

### Fixed contract

- Buffer: 256 volatile 32-bit words
- Iterations: 2,048
- Seed: `0x6D5A56E9`
- Golden checksum: `0x46FC5BC9`
- START/END: `0x504F5752` / `0x454E4421`
- Marker ELF symbol/address: `p0_mix_marker` / `0x80000410`

### Commands

```powershell
python .\power\workloads\p0_mix\reference_model.py
wsl.exe -e bash -lc "cd /mnt/d/Rsicv-soc-worktrees/phase2-act4-cleanup && bash sw/build_firmware_wsl.sh --install p0_mix"
cd sim/regress
.\run_regression.ps1 -Manifest .\power_tests.json -Test p0_mix
```

### Results

- Independent checksum model: PASS, `0x46FC5BC9`
- ELF size: 856 text bytes, 0 data bytes, 1,044 BSS bytes
- Disassembly audit: `mul`, `divu`, and `remu` are present
- RTL regression: PASS at cycle 345,948 with `tohost = 1`
- Timer interrupts / UART bytes / GPIO transitions: `0 / 0 / 0`
- Simulator errors: 0; 17 existing relaxed-input/default warnings

The cycle value includes startup and final checking; it is not the marker-window
cycle KPI.

### SHA-256

| Artifact | SHA-256 |
|---|---|
| `sw/apps/p0_mix/main.c` | `35C8EA1A159A59CD212B577081EB28A9AB7E61867F22E235DCA37C94FF353F46` |
| `reference_model.py` | `DB61177D05076E53A6F07F36CCC477F4122B331B5EC807E37818586D882ECF5A` |
| `firmware_p0_mix.imem.hex` | `859E8B3C9FF11041FBD34C07992608470C019131EB4E0EEBBA076239B9EB97AA` |
| `firmware_p0_mix.dmem.hex` | `6B818C87E1A60F732E8269F6A9BD3854F2DAFAD7C93DD9D88DFC99B810D63F56` |
| Generated ELF | `C7F3A47948BE6A4A1BF87613939BA2347D2585C31F691ABE0D1B16BE0757E695` |

## Routed activity and power — 2026-09-17

### Measurement identity

- Simulation hierarchy: `tb_power/u_soc`; Vivado strip path: `tb_power`
- Routed hierarchy: `top/u_soc`
- Part/tool: provisional `xc7z010clg400-1`, Vivado 2019.2
- Clock: exact 95 MHz MMCM profile
- Checkpoint SHA-256: `07F9962FA1BCFED99A17C0518EA749F09B8C1611E99EBEEF6874A016A7D96032`
- Checkpoint timing: WNS `+0.006 ns`, TNS `0.000 ns`; all constraints met
- DRC: no Error/Critical Warning; 38 retained advisory warnings
- Capture interval: START cycle 7,851 to END cycle 345,894
- Fixed work: 338,043 cycles, 117,768 retired instructions, 2,048 iterations

### Commands

```powershell
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_mix -RunId run5
.\power\scripts\run_modelsim_saif.ps1 -Workload p0_mix -RunId run6
python .\power\scripts\make_saif_dsp_bridge.py <run>\p0_mix.saif <run>\dsp_bridge.tcl <run>\dsp_bridge.json
vivado -mode batch -source .\power\scripts\analyze_vivado_power.tcl -tclargs <95MHz.dcp> <run.saif> <output> tb_power <dsp_bridge.tcl>
python .\power\scripts\check_block_coverage.py .\power\workloads\p0_mix\mapping_coverage.json <switching.rpt> <simulation.log> <dsp_bridge.json> <block_coverage.json>
python .\power\scripts\summarize_power_run.py <run> --vivado-subdir vivado_reviewed --reviewed-alternative <block_coverage.json>
python .\power\scripts\compare_power_runs.py <run5> <run6> <repeatability.json>
```

Angle-bracket paths above are resolved generated paths under ignored `build/`;
the scripts reject missing inputs and failing gates.

### Mapping decision

Vivado directly matched only 481 of 8,746 design nets (`5.500%`). The previous
4% result was not primarily a workload failure: ModelSim names packed fields as
for example `pkt2ex_q.ex_data.op1[31]`, while synthesis emits names such as
`pkt2ex_q_reg[ex_data][op1][31]` and absorbs combinational multiplier signals.

REQ-P0-004 explicitly permits a reviewed block-level alternative. The checked
alternative requires direct `(S)` or clock-derived `(C)` coverage of the clock,
pipeline/regfile, LSU/fabric, both BRAM boundaries, divider, and idle peripheral
boundaries. Multiplier RTL SAIF records nonzero `lhs_ext`, `rhs_ext`, and
`product_ext` activity; their measured mean rates are explicitly applied to the
four routed DSP48 cells, producing 540 `(A)` annotated routed nets. All ten
required block gates pass. This result must not be described as 80% direct
mapping.

### Power and repeatability

| Metric | Vectorless | Reviewed activity run 5 | Reviewed activity run 6 |
|---|---:|---:|---:|
| Total on-chip power | 0.207 W | 0.220 W | 0.220 W |
| Dynamic power | 0.115 W | 0.127 W | 0.127 W |
| Device static | 0.093 W | 0.093 W | 0.093 W |
| Confidence | Medium | Medium | Medium |

Dynamic-power difference is `0.0%`, passing the `<=2%` gate. At fixed work,
the reviewed estimate is `2.2066e-7 J/iteration` (220.66 nJ/iteration).

### Artifact hashes

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Routed checkpoint | 3,343,815 | `07F9962FA1BCFED99A17C0518EA749F09B8C1611E99EBEEF6874A016A7D96032` |
| Closed timing report | 305,570 | `08E2AD25ADAC9EB738AA43E7A5ACFF8E302D1137F2816447AAB4364CCE129D3A` |
| Closed DRC report | 24,527 | `8C310F7E29945B9FDC545A0A943B6AAC59662BAB1488D9B7F310CDF6524AD003` |
| Run 5 SAIF | 1,364,458 | `FB1D441C582C8E00928A7E14DFDBE02EA3E75127C5F05955EC79601FC4D87AA3` |
| Run 6 SAIF | 1,364,458 | `336FCF9D089B277EB4451C27AF095EF4058633C9DEFF16D9AF4908A5E8AD9CF6` |

The raw SAIF hashes differ only because the SAIF `DATE` header differs; both
ModelSim activity-report hashes and every extracted metric are identical.

### Limitations

- The accepted estimate is a reviewed hybrid: directly mapped RTL activity,
  explicit measured DSP bridging, clock constraints, and probabilistic
  propagation for the remaining optimized combinational cone.
- RTL SAIF omits routed glitches. Full-board gate simulation was tested in both
  ModelSim and XSim but did not reach START within a four-minute feasibility
  bound, so it is retained only as a forensic path.
- Default Vivado environment assumptions and the provisional board part/speed
  grade are recorded; the result is not board-rail, thermal, ASIC, or silicon
  sign-off power.
- The unused PS7 emits a power-property warning and contributes 0 W in the
  report; it is outside the measured programmable-logic workload.
