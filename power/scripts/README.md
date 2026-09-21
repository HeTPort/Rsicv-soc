# Power Framework Scripts

The scripts are separated by stage so that a downstream report change never
forces another firmware build, simulation, or route.

| Stage | Intended tool | Status |
|---|---|---|
| Contract validation | `validate_workloads.py` | Implemented |
| Firmware build/install | `sw/build_firmware_wsl.sh --install <app>` | Implemented for bare-metal workloads; FreeRTOS uses the documented `_p0` build flags |
| Functional ModelSim run | `sim/regress/run_regression.ps1 -Manifest power_tests.json` | Implemented |
| SAIF/VCD capture | `run_modelsim_saif.ps1` and `power/common/capture_window.do` | Implemented |
| 95 MHz route | `fpga/zynq_mini_revb/build.tcl` with `ZYNQ_MINI_CORE_CLOCK_HZ=95000000` | Implemented |
| Post-route timing closure | `close_95mhz_timing.tcl` | Implemented |
| Routed vectorless/SAIF comparison | `analyze_vivado_power.tcl` | Implemented |
| Optimized-net activity bridges | `make_saif_dsp_bridge.py`, `make_saif_timer_bridge.py` | Implemented; require review |
| Block mapping gate | `check_block_coverage.py` with workload policy | Implemented |
| One-run power verdict | `summarize_power_run.py` | Implemented |
| Repeat comparison | `compare_power_runs.py` | Implemented |

Use the exact routed checkpoint for the workload and 95 MHz profile; the
production 25 MHz checkpoint is not interchangeable. First pass the functional
regression, then run `run_modelsim_saif.ps1 -Workload <name> -RunId <id>` twice.
Each run compiles into its own ignored `modelsim/` subdirectory, so captures
do not share a mutable ModelSim work library.
Add `-DumpVcd` only for hierarchy/debug inspection. For each run, generate any
required bridge Tcl/JSON, invoke `analyze_vivado_power.tcl` against that same
checkpoint, run `check_block_coverage.py`, and run `summarize_power_run.py`
with `--reviewed-alternative`. Finally use `compare_power_runs.py` on the two
run directories. Exact invocations and artifact hashes are recorded in each
workload's `results.md`.

Raw mapping near 5.5% is not a pass by itself. A bridge maps measured RTL
activity to reviewed routed objects; it must be accompanied by the block policy
and its PASS result. Do not present bridge-annotated power as a directly mapped
80% SAIF result or as a physical board measurement.
The DSP bridge records original SAIF probability and any <=0.0001 absolute
adjustment needed to satisfy Vivado's legal toggle/probability bound. A larger
inconsistency fails instead of silently changing measured activity. The
`p0_idle_spin` first unadjusted import was rejected and its corrected runs are
retained under `vivado_reviewed_corrected/`.
Run `python power/scripts/test_bridge_bounds.py` for the focused legal,
quantization, material-inconsistency, and impossible-toggle checks.

Scripts must return a nonzero exit for missing files, functional failure,
unacceptable mapping, timing/DRC failure, or malformed reports. Merely creating
an output file is never PASS.
