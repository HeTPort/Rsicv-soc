# P0 Reproducible Power Baseline — Measurement Architecture

**Phase:** P0 — Reproducible power baseline
**Status:** Accepted
**Owner:** HeTPort
**Last updated:** 2026-09-20
**Depends on:** `REQ-P0-*`; existing ModelSim regression and Vivado routed flow
**Related evidence:** [`requirements.md`](requirements.md), [`verification_plan.md`](verification_plan.md),
[`../../../power/README.md`](../../../power/README.md)

## Context and boundary

P0 wraps the existing testbenches and FPGA implementation. It does not alter
the DUT data/control path. Existing directed test manifests supply program,
timeouts, generics, and PASS/FAIL; a capture layer controls only the observation
hierarchy and measurement window.

## Block/data-flow diagram

```text
fixed workload + manifest + RTL
              |
              v
   ModelSim marker/result/tohost PASS -> marker-bounded VCD (optional debug)
              |
              +-------------------> marker-bounded backward SAIF
                                         |
matching 95 MHz routed DCP + XDC ---------+
                                         v
                         read_saif + match report
                         + reviewed DSP/timer Q bridges
                         + per-block coverage policy
                                         |
                                         v
                         vectorless/activity report_power
                         + two-run comparison and KPI verdict
```

## Interfaces and protocols

- **Workload identity:** manifest name, firmware/hex hash, RAM configuration,
  timeout, testbench top, and terminal `tohost`/firmware oracle.
- **Capture identity:** DUT hierarchy, start event/cycle, stop event/cycle,
  simulated duration, clock period, VCD/SAIF hash, and file size.
- **Vivado identity:** implemented checkpoint/bitstream hash, part, speed grade,
  XDC clock, tool version, environment assumptions, `read_saif -strip_path`,
  and match/unmatched report.
- **Result identity:** vectorless and activity-based reports from the same
  implementation plus a compact scenario comparison.

The implemented flow uses `tb_power/u_soc` and observes committed START/END
stores to a workload-specific, ELF-resolved RAM marker. `capture_window.do`
records only that interval with ModelSim `power add`, `power on/off`, and
`power report -bsaif`; optional VCD shares the interval. `tohost` is a separate
terminal oracle. `read_saif -strip_path tb_power` targets `top/u_soc` in the
same routed DCP used for vectorless power. The WFI checkpoint pins
`TIMER_TICK_CYCLES=1` to match simulation. Generated files live under ignored
`build/power/`, with compact evidence in workload `results.md` files.
Each run compiles into an isolated ignored ModelSim work library, so parallel
captures cannot overwrite each other's elaboration state. The FreeRTOS `_p0`
image uses a fixed 16-queue-receive window after 12 warmup receives, with
committed post-window tick/LED/heartbeat counters. The UART scenario brackets
14 fully transmitted polling bytes. The spin-idle scenario brackets 65,536
register-only loop iterations; it remains clocked, unlike WFI.

## Clock, reset, CDC/RDC, and safe-state strategy

P0 introduces no clock/reset logic. Each activity window begins only after
reset deassertion and required boot initialization. Clock toggles come from the
XDC timing definition in Vivado; UG907 notes that SAIF import does not override
design clock activity. Existing asynchronous UART input synchronization and
timer behavior remain unchanged.

## State machines and timing

The capture controller has four observational states:

```text
SETUP -> FUNCTIONAL_WARMUP -> CAPTURE -> FLUSH_AND_REPORT
             |                  |
             +---- failure -----+----> FAIL
```

Capture start/stop must be deterministic: preferably a testbench event or a
known architectural marker, otherwise an exact post-reset cycle range. A
timeout or missing terminal oracle is failure even if an activity file exists.

## Data representation

- Time is recorded in simulator units and equivalent clock cycles.
- Power is reported in watts/milliwatts exactly as emitted by Vivado.
- Activity files are identified by SHA-256; large files are not committed.
- Percentage deltas always name baseline, workload, and denominator.

## Error and fault containment

- Missing/empty activity, SAIF parse failure, inadequate direct mapping without
  a passing reviewed per-block alternative, negative timing, or functional
  FAIL prevents an accepted power result.
- Vectorless fallback is reported separately, never silently called activity-
  based evidence.
- A DSP bridge rejects probability/toggle inconsistencies greater than
  0.0001 absolute. The smaller ModelSim clock-window quantization in the
  spin-idle run is explicitly bounded, adjusted, and recorded; its original
  Vivado rejection remains retained.
- Filesystem-size limits are enforced by narrow hierarchy/window selection,
  not by truncating a file and treating it as valid.

## Alternatives and decision links

- **UVM:** unnecessary for activity generation; directed workload correctness
  remains enough for P0.
- **cocotb:** useful later for workload orchestration, but adds Python/tool
  integration without solving SAIF mapping.
- **Verilator:** useful for fast legal open-source simulation, but the current
  project is already proven in ModelSim and tool migration is separate work.
- **Board rail measurement:** more physically meaningful later, but cannot
  isolate internal block activity and needs instrumentation/hardware.

See
[`../../ar/AR027_RTL_COMMON_AND_MULTIPLIER_PIPELINE_REVIEW.md`](../../ar/AR027_RTL_COMMON_AND_MULTIPLIER_PIPELINE_REVIEW.md)
for why P0 precedes multiplier and low-power RTL changes.

## Implementation partition

| Layer | Ownership |
| --- | --- |
| Existing manifests/testbenches | Functional workload and PASS/FAIL |
| `power/` workload packages | Per-workload intent, fixed-work/window contract, expected activity, KPIs, and structured identity |
| ModelSim capture Tcl/wrapper | Window, hierarchy, VCD/backward-SAIF, hashes |
| Vivado power Tcl and bridge scripts | Open exact routed checkpoint, `read_saif`, measured optimized-net bridges, match/switching/power reports |
| `doc/plans/p0-power-baseline/results.md` | Compact evidence and limitations |

No source/common RTL or MMIO register is part of P0.
