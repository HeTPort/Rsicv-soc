# P0 Reproducible Power Baseline — Results

**Phase:** P0 — Reproducible power baseline
**Status:** Active; simulator activity spike complete, Vivado mapping not run
**Owner:** HeTPort
**Last updated:** 2026-09-07
**Depends on:** [`verification_plan.md`](verification_plan.md)
**Related evidence:** Existing Phase 7 routed reports; no accepted P0 activity evidence yet

## Tested identity

| Item | Observed value |
| --- | --- |
| Repository state | Working tree with P0 documentation; exact commit/tree not yet frozen |
| Host/tool probe | Windows; ModelSim SE-64 2019.2 command line available |
| Functional spike | `rv32im`, `testdata/prog.hex`, 20,000-cycle timeout; PASS at cycle 672, simulator exit 0 |
| VCD evidence | `tb_riscv.vcd`, 6,093,088 bytes, SHA-256 `ED3559F2B5B9173F478885814BF710E9E57257D390CF74424DA03227F1637306` |
| Backward-SAIF evidence | SAIF 2.0, duration 6,825,000 ps, 1,083,410 bytes, SHA-256 `2F0EE9EC35E70FFA875CC10B367F77A948DAB01887F3AD8F4EFDAD92B19D45F1` |
| ASCII activity evidence | 1,543,897 bytes, SHA-256 `020CA0A0A97A534E934BFC62B0CD263462379F158C22A5D572B551B8CDFD354E` |
| Vivado activity import | FORMAT PASS / QUALITY REJECTED: 419 of 10,927 design nets matched (4%) in OOC spike |
| Target checkpoint/bitstream | NOT SELECTED |

## Regression summary

One full-run simulator activity spike has executed. It proves that the current
RTL/testbench can pass while producing VCD and backward-SAIF. Because the
window includes reset/boot and no Vivado mapping has run, it is capability
evidence rather than an accepted workload power baseline.

| Command/gate | Result |
| --- | --- |
| ModelSim VCD command capability probe | PASS |
| ModelSim backward-SAIF command capability probe | PASS (command/documentation only) |
| `rv32im -DumpWaves` functional workload | PASS; 672 cycles; VCD generated |
| `rv32im` full-run backward-SAIF capture with `onfinish stop` | PASS; SAIF/activity report generated |
| Vivado `read_saif` format/mapping spike | PARSE PASS; mapping FAIL at 419/10,927 nets (4%); no user clock |
| Duplicate-run comparison | NOT RUN |

## Focused evidence

`REQ-P0-003` is partially demonstrated: nonempty VCD/backward-SAIF came from a
functionally passing run. Its accepted post-reset/windowed form and every
Vivado-facing requirement remain open. The first attempt omitted
`onfinish stop`; testbench `$finish` ended the simulator before `power report`,
producing no SAIF. The corrected command intentionally makes `$finish` return
control to Tcl before reporting.

`REQ-P0-004` is not met. Vivado 2019.2 successfully parsed the backward-SAIF,
but the core-RTL hierarchy mapped only 419 of 10,927 design nets into the older
OOC synthesized SoC checkpoint. The retained mapping report is 976,281 bytes,
SHA-256 `A106C942346D32D5B23B6A1E8E4C41D962C4814270EEAF5A50F3F1BC09EF6B3C`.
The diagnostic power report is 9,861 bytes, SHA-256
`C10681BD5894C199AD2570A6CFA8F5E001CD278BA8EDA946E6E48B67AF4E0A46`.

## Commands used for the capability spike

```powershell
Set-Location sim/regress
.\run_regression.ps1 -Test rv32im -DumpWaves
```

The backward-SAIF retry used ModelSim `onfinish stop`, added
`/tb_riscv_core/u_riscv/*` recursively, enabled activity, ran to the existing
functional `$finish`, disabled activity, and called `power report -bsaif`.
Vivado then opened `build/vivado_ar003/riscv_soc_synth.dcp` and used
`read_saif -strip_path tb_riscv_core`. The exact generated Tcl and large
activity outputs remain under ignored `sim/build/regression/`.

## Synthesis/implementation

Existing routed Phase 7 images report positive 25 MHz timing and zero DRC
errors, but P0 has not selected/frozen one checkpoint. LUT/FF/BRAM/DSP and
WNS/TNS must be copied from that exact implementation when the first activity
run is accepted.

## Power/performance

| Workload | Window | Activity source | Mapping | Vectorless | Activity-based | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Reset/idle | NOT SET | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| WFI+timer | NOT SET | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| UART polling | NOT SET | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| FreeRTOS | NOT SET | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Compute/memory (`rv32im` spike) | Full 0–6,825 ns, includes reset/boot | VCD + backward-SAIF generated | 4%, rejected | OOC diagnostic only | 17.583 W, Low confidence, **REJECTED** | PARTIAL capability only |

## Hardware/model evidence

No board rail measurement, thermal model, ASIC library power analysis, motor,
compressor, plasma, or flight evidence is part of P0.

## Known limitations and confidence

- ModelSim installation presence does not prove the user's license entitlement.
- RTL functional activity omits routed glitch activity.
- This first capture includes reset/boot and is not an accepted steady-state
  measurement window.
- Vivado 2019.2 format compatibility is proven, but mapping is only 4% against
  the selected OOC checkpoint.
- The OOC checkpoint has no user-defined clock; Vivado also warned that reset
  was asserted excessively for the activity interval.
- The user's recent 75 MHz result is not in this package and lacks retained
  configuration/path evidence here.

Confidence is currently **capability-only**, not measurement confidence.

## Exit-gate verdict

**PARTIAL.** The local simulator produced real VCD/backward-SAIF activity from
a passing RV32IM workload and Vivado parsed it. The 4%-mapped, clockless,
reset-inclusive 17.583 W report is explicitly rejected. No workload-derived
power number is accepted until a post-reset scoped window, Vivado import/
mapping/report path, repeat run, and negative infrastructure test pass.
