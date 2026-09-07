# Roadmap and Learning Path

**Document type:** staged program roadmap and knowledge dependency map

**Status:** Accepted planning baseline; implementation evidence remains in each
phase package and existing AR reports

**Last updated:** 2026-09-07

## 1. What this roadmap represents

The repository is currently a verified **experimental RV32IM control-SoC
foundation**, not a complete propulsion controller and not evidence that the
long-term flight concept is feasible.

The long-term vision may be stated as:

> Explore an atmospheric propulsion and control platform that combines a
> mechanically compressed inlet/front end with electrically assisted or
> electric propulsion at altitude, supported by safe power electronics,
> sensing, control, and heterogeneous computation.

That vision is a research program, not one indivisible coding project. The
program should be split into evidence-producing projects:

1. custom control SoC and verification platform — this repository;
2. low-order electrical/mechanical/fluid plant models and control software;
3. safe actuator, sensor, and power-electronics interfaces;
4. bench-scale compressor/motor/flow experiments;
5. propulsion/energy/thermal feasibility and mission-level trade studies;
6. only much later, integrated flight hardware and assurance work.

Calling the repository an "experiment" is accurate and useful, but the title
does not reduce the need to distinguish planned, simulated, synthesized,
FPGA-verified, bench-tested, and flight-qualified claims.

## 2. Planning rules

Every active phase follows the same engineering loop:

```text
requirement + failure consequence
        -> interface and observable contract
        -> reference model / expected behavior
        -> smallest vertical implementation
        -> positive + boundary + negative + fault verification
        -> timing/resource/power/performance evidence
        -> documented exit gate
        -> next phase
```

Use [`PHASE_EVIDENCE_TEMPLATE.md`](PHASE_EVIDENCE_TEMPLATE.md) when a phase
becomes active. `TODO.md` remains the detailed checkbox ledger; this roadmap
owns dependency order, learning goals, decision gates, and scope boundaries.

Do not implement optional accelerators merely to make the block diagram look
complete. A phase begins only when its prerequisite evidence exists.

## 3. Current baseline

Already demonstrated in this repository:

- custom RV32IM core, precise retirement/traps, wait-state LSU, SoC fabric;
- timer, polling UART TX/RX, output GPIO, bare-metal runtime, FreeRTOS port;
- directed regression, official ACT4 RV32I/RV32M baseline, focused assertions;
- Vivado synthesis/route and physical Zynq board execution evidence.

Not yet demonstrated:

- implemented UVM framework or ISS differential checking;
- completed representative workload power baseline or physical low-power state
  (P0 is active; a format spike ran but its 4% mapping was rejected);
- performance-monitor counters beyond the existing architectural baseline;
- safe PWM/capture/watchdog/fault-shutdown control slice;
- ADC/SPI/interrupt/DMA sampled-data path;
- a validated motor/compressor/flow plant model or SIL/HIL loop;
- workload-justified custom accelerator, RVV/NPU, GPU, or propulsion feasibility.

## 4. Dependency waves

| Wave | Active focus | May proceed in parallel | Must remain gated |
| --- | --- | --- | --- |
| 0 | Documentation/release readiness | Adopted license, reference indexing | Default-branch integration/push requires explicit later approval |
| 1 | P0 measurement-only power baseline | U0 passive UVM when a legally entitled tool path is chosen | No active agents, ISS, or RTL power change |
| 2 | P1 counters/safe sleep after P0 | U1 ISS then U2 generated ISA after U0 | No NPU/GPU; no unmeasured clock gating |
| 3 | C0 safe control vertical slice | M0 low-order MIL/SIL model | No high-energy bench actuation |
| 4 | C1 ADC/SPI/IRQ/DMA | M0 RTL/software-in-loop coupling | DMA only after interrupt/MMIO contracts |
| 5 | A0 small MMIO accelerator | Refine HIL/bench model correlation | Accelerator only after profiling |
| 6 | A1 RVV/NPU study or G0 GPU research | Product/propulsion feasibility work in separate repos | Entry only if decision gates pass |

## 5. Detailed stages

### R0 — Documentation, licensing, and release readiness

**Outcome:** an external reviewer can tell what is implemented, reproduce the
evidence, understand limitations, and know what reuse rights exist.

**Prerequisites:** current green release baseline and clean attribution of
third-party material.

**Implementation:**

1. keep README claims tied to retained evidence;
2. maintain this roadmap, reference index, phase template, and release
   checklist;
3. retain the adopted root license/scope and commercial contact consistently;
4. inventory third-party code/models/assets with upstream version and license;
5. later prepare a reviewed integration PR into `main`; do not merely switch
   the GitHub default branch to an unreviewed development branch.

**Knowledge:** copyright versus patent/trademark/trade secret, provenance,
semantic versioning, release artifacts, CI/reproducibility.

**Exit gate:** license scope is explicit; third-party provenance is complete;
README/TODO/living documents agree; release command is green; integration diff
is reviewable. Default-branch work remains deferred in the present task.

### U0 — Passive UVM retirement vertical slice

**Outcome:** UVM independently observes existing architectural retirement and
detects a deliberate mismatch without driving the DUT.

**Prerequisites:** stable `commit_pkt_t`, `trap_entry_t`, `tohost` semantics,
and installed ModelSim/Questa version.

**Implementation:**

1. compile the smallest supported UVM smoke and pin version/invocation;
2. create only the retirement domain, interface, adapters, core environment,
   test, and script needed now;
3. map commit and asynchronous trap-entry records losslessly into separate
   transaction types;
4. add a clocking-block passive monitor, ordered scoreboard, tohost subscriber,
   and initial coverage;
5. inject one mismatch and require a native nonzero result;
6. preserve focused retirement, 23/23 smoke, ACT4, and release gates.

**Knowledge:** UVM components/phases/configuration, analysis ports, monitor
sampling, reference/predicted versus observed streams, objection/end-of-test,
functional coverage, deterministic failure reporting.

**Exit gate:** passive results agree with existing checks, deliberate mismatch
fails, no DUT timing changes, and regression overhead is recorded.

### U1 — ISA differential checking

**Outcome:** every supported retired instruction can be compared with a typed
reference-model adapter.

**Prerequisites:** U0 stable retirement ordering and one authoritative memory
and MMIO synchronization policy.

**Implementation:** select Spike, Sail, or another reference; place it behind a
model-neutral adapter; start with existing directed tests; define trap,
interrupt, CSR, memory, and tohost synchronization; preserve each mismatch as a
minimal regression.

**Knowledge:** architectural state, differential testing, ELF/memory images,
reference-model stepping, nondeterministic MMIO/interrupt boundaries.

**Exit gate:** selected directed corpus compares continuously with reproducible
diagnostics and no hidden manual state repair.

### U2 — Generated instruction workloads

**Outcome:** reproducible random programs explore instruction and transition
combinations beyond directed tests.

**Prerequisites:** U1 trustworthy comparison and exact supported-ISA/CSR model.

**Implementation:** define an RV32IM M-mode riscv-dv target; exclude unsupported
features; archive seed/config/program/tool versions; triage timeout,
environment, model, and DUT failures separately; retain ACT4 as the standards
gate.

**Knowledge:** constrained random generation, coverage closure, seed reduction,
test classification, capability descriptions.

**Exit gate:** a fixed generated suite is reproducible, failures are minimized
and classified, and coverage gaps drive targeted tests.

### U3 — Reactive agents and generated register model

**Outcome:** memory/peripheral latency/error behavior and software-visible
registers can be verified through reusable agents and one register source.

**Prerequisites:** frozen bus timing/error contracts and one successful
SystemRDL/PeakRDL pilot.

**Implementation:** add reactive memory agents only after authority/ordering is
defined; generate documentation/C/UVM/RTL consumers from one register source;
add virtual sequences without leaking protocol handles into semantic
scoreboards.

**Knowledge:** sequencer/driver protocols, UVM RAL, prediction/mirroring,
frontdoor/backdoor access, reset/access policies, generation pipelines.

**Exit gate:** generated consumers are stale-checked, register reset/access/
side-effect tests pass, and random wait/error injection preserves architectural
correctness.

### P0 — Reproducible power baseline

**Current status:** Active. The accepted package is
[`plans/p0-power-baseline/`](plans/p0-power-baseline/). One RV32IM run produced
VCD/backward-SAIF and Vivado parsed it, but only 4% of the older OOC design nets
mapped and no clock was present; the resulting number is rejected, so no
accepted baseline exists yet.

**Outcome:** power changes can be compared under fixed workloads rather than
estimated from intuition.

**Prerequisites:** stable bitstream/synthesis profile and representative test
workloads.

**Implementation:** define reset/idle, WFI+timer, UART polling, FreeRTOS,
memory-heavy, and later control-loop workloads; capture VCD/SAIF over stated
windows; record tool/part/clock/constraints/activity mapping; compare vectorless
and activity-based Vivado reports; save compact reports and uncertainty.

**Knowledge:** dynamic versus static power, switching activity, SAIF mapping,
clock/resource power, workload normalization, confidence/assumptions.

**Exit gate:** two independent reruns of the same workload produce comparable
results and explain dominant activity/resources. P0 changes measurement only.

### P1 — Counters and truthful low-power state

**Outcome:** software can explain CPU time/activity and request sleep only when
the core/SoC is genuinely safe to stop.

**Prerequisites:** accepted P0 baseline and regression/observation strong enough
to detect changed retirement/wakeup behavior. U0 passive observation is useful
but not mandatory if directed tests and assertions cover the P1 contract.

**Implementation:** preserve and extend verification of the existing `mcycle`
and `minstret`; add `mcountinhibit`, then parameterized events for stalls,
LSU/divider/fetch waits, sleep cycles, and bus transactions; expose
`sleep_safe` only for retired WFI with no outstanding work/redirect/trap; use
clock enables/vendor clock resources on FPGA; keep timer/wakeup alive; add
RUN/IDLE_REQUEST/IDLE/WAKE states and a wake-cause record.

**Knowledge:** RISC-V PMU semantics, clock enable versus clock gating, FPGA
clocking primitives, quiescence handshakes, wake races, liveness assertions.

**Exit gate:** no lost/duplicate interrupt, bounded wake, counter semantics
verified around reset/trap/WFI/inhibit, unchanged program results, reproducible
power delta versus P0.

### C0 — Safe control peripheral vertical slice

**Outcome:** the SoC can generate and observe a low-energy closed-loop control
signal and reach a safe output state independently of CPU response time.

**Prerequisites:** accepted requirements and safe-state/failure-consequence
analysis; use simulation or low-voltage benign loads first.

**Implementation:** PWM with edge/center mode, shadowed period/compare,
complementary outputs/dead time and update boundary; edge capture/timestamp;
bark/bite watchdog; direct external fault-to-output kill, sticky cause, IRQ,
explicit clear; firmware driver and reference waveform model.

**Knowledge:** timer/PWM design, dead time, actuator safe states, synchronizers,
shadow registers, temporal assertions, ISR latency versus hardware protection.

**Exit gate:** no complementary overlap, bounded fault-to-safe latency even
with frozen CPU, reset is safe, wrap/update/fault-clear corner tests pass, and
small firmware demo closes the loop with a model.

### C1 — Sampled-data path: SPI/ADC, interrupts, and DMA

**Outcome:** deterministic sensor samples reach memory/control code with
defined timing, buffering, errors, and backpressure.

**Prerequisites:** one representative ADC timing contract, C0 control-period
requirements, and frozen interrupt semantics.

**Implementation:** SPI master and ADC testbench model; conversion/data-ready
timing, RX FIFO, error/complete events; small interrupt controller with pending,
enable/mask, priority/claim or documented simpler scheme; DMA memory-to-memory
first, then peripheral-to-memory circular/double buffer; alignment, abort,
timeout, error and IRQ tests.

**Knowledge:** SPI modes/framing, ADC sampling and aliasing, FIFO/backpressure,
interrupt level/pulse/W1C semantics, DMA descriptors, memory ordering.

**Exit gate:** register and protocol tests pass; samples are neither dropped nor
duplicated within declared limits; DMA integrity/error recovery and firmware
driver smoke are green; latency/jitter is measured.

### M0 — Low-order plant model, MIL, and SIL

**Outcome:** control behavior is tested against a versioned electrical,
mechanical, and fluid approximation before expensive hardware.

**Prerequisites:** explicit units/signs/sample rate and plausible parameter
ranges; the model is not presented as validated propulsion physics.

**Implementation:** begin in Python/C++ with motor/inverter approximation,
shaft inertia/friction, compressor pressure-flow lag, sensor noise/
quantization/saturation; define timestamp/command/sensor/fault/status contract;
MIL with ideal controller; SIL by compiling the same C control function used by
firmware; later connect RTL through DPI/socket/FMI; test startup, sweep, step,
disturbance, sensor faults, overcurrent, watchdog, jitter, saturation/recovery.

**Knowledge:** state-space/discrete systems, numerical integration, stability,
sampling, anti-windup, filters/observers, parameter identification, model
verification versus physical validation.

**Exit gate:** nominal response and fault deadlines meet stated thresholds,
units/conservation sanity checks pass, runs are reproducible, uncertainty and
unvalidated parameters are explicit.

### M1 — HIL and low-energy bench correlation

**Outcome:** real FPGA/controller timing is exercised against a real-time plant
simulation, then correlated with safe bench measurements.

**Prerequisites:** M0 stable model, C0/C1 interfaces, hardware protection,
instrumentation plan, and safe low-energy test boundary.

**Implementation:** fixed-rate host/MCU plant simulator; real controller I/O;
fault injection and latency measurement; then motor/compressor subcomponent
tests with current/voltage/speed/pressure/temperature logging; fit parameters
and keep pre/post-correlation model versions.

**Knowledge:** real-time scheduling, I/O scaling/isolation, instrumentation,
uncertainty, system identification, lab safety.

**Exit gate:** hardware/software timing and protection meet thresholds; model
error is quantified across a declared operating envelope. Human-carrying or
high-energy integrated tests remain out of scope.

### A0 — Profile-driven small MMIO accelerator

**Outcome:** one measured control/signal-processing kernel is accelerated
end-to-end, including transfer overhead and software API.

**Prerequisites:** P1 counters and at least one stable C0/M0 workload showing a
repeatable hotspot.

**Implementation:** choose FIR, Clarke/Park, fixed small matrix, or batch filter;
freeze numeric format/tolerance; write C golden model; use version/control/
status/operand/result/error/IRQ registers; one command and no DMA first; measure
CPU versus accelerator cycles, bytes, area, active power, and energy; add FIFO/
scratchpad/DMA only when measured.

**Knowledge:** profiling, fixed point, arithmetic intensity, MMIO ABI, locality,
scratchpad/DMA, bit-exact verification.

**Exit gate:** realistic workload is faster or lower-energy end-to-end; timeout
and error recovery work; driver/API and regression are stable.

### A1 — Optional RVV or CoralNPU integration study

**Outcome:** decide with evidence whether programmable vector/ML compute is
worth its memory, compiler, verification, and power cost.

**Entry gate:** at least two real vector/ML workloads; A0 too narrow or
insufficient; high-throughput memory/bus budget; compiler/runtime ownership;
context, interrupt, verification, and power-state plans.

**Study:** compare CPU/A0/RVV/NPU using end-to-end data movement; prototype
software toolchain first; evaluate AXI/TCM/scratchpad adaptation and duplicate
CPU/memory cost; do not call Ara or CoralNPU drop-in components for the current
CoreBus SoC.

**Exit gate:** written go/no-go decision with workloads, memory bandwidth,
area/power estimates, software plan, and verification scope. No gate means
remain deferred.

### G0 — Optional GPU/GPGPU research track

**Outcome:** learn the complete GPU stack or justify integration without
destabilizing the control SoC.

**Entry gate:** a product requirement for programmable graphics/GPGPU that
CPU/A0/RVV/NPU cannot satisfy; DDR/PCIe-class bandwidth; compiler/runtime/
driver ownership; synchronization/memory-model verification; separate power
domain budget.

**Study:** use Vortex as a full-stack reference—simulator, RTL, FPGA backend,
driver, toolchain, OpenCL/OpenGL—rather than designing an isolated "GPU ALU".

**Exit gate:** research branch results and go/no-go decision. G0 is not on the
critical path for control, power management, or the first propulsion model.

## 6. Knowledge architecture

Learn and apply knowledge in dependency order:

1. **Foundations:** digital logic/timing; SystemVerilog; C/C++/assembly; RISC-V
   ISA/CSR; basic linear algebra, signals, mechanics, fluids, and controls.
2. **Contracts:** MMIO/register semantics; valid/ready; ordering; interrupts;
   FIFO; CDC/RDC/reset; numeric formats; physical units and sign conventions.
3. **Implementation:** CPU/SoC RTL; peripherals; firmware/RTOS; host models;
   FPGA build and bring-up.
4. **Evidence:** directed tests; SVA; UVM/ISS; coverage; fault injection;
   regression; synthesis/timing/resources; power; MIL/SIL/HIL.
5. **System design:** safe control states; sampled-data path; DMA; low power;
   model correlation; workload-driven acceleration.
6. **Optional advanced branches:** AXI/DDR/Linux; RVV/NPU; GPU/OpenCL/Vulkan;
   CFD/plasma/thermal/mission optimization.
7. **Product assurance:** provenance/release/CI; traceability; configuration;
   hazard analysis; later hardware/software development assurance.

AI assistance can accelerate implementation, but the learning checkpoint for
each phase is the ability to explain the contract, predict a failure, identify
the checker that catches it, and reproduce the evidence without trusting AI
output as proof.

## 7. Near-term order

The next implementation sequence is:

1. finish the remaining R0 provenance/release review without changing the
   default branch; the repository license decision is adopted;
2. execute P0 from one short workload through ModelSim activity capture and
   Vivado `read_saif`/mapping before changing power RTL;
3. implement U0 when desired using the bundled/legally entitled UVM path, or
   evaluate current Verilator/cocotb separately; U0 does not block P0;
4. implement P1 only after P0 and implement U1 only after U0;
5. implement C0 and the M0 low-order model as the first propulsion-relevant
   vertical slice;
6. add C1 sampled-data infrastructure;
7. profile the resulting workload before A0;
8. keep A1/G0 deferred unless their entry gates are proved.
