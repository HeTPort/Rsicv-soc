# AR-026 — Scalable UVM Verification Architecture

**Date:** 2026-09-02

**State:** Accepted; implementation not started

**Stage:** Continuous verification and post-release expansion

## 1. Problem

The current verification stack is strong for the implemented single-hart
RV32IM SoC: directed assembly and firmware tests, committed `tohost` results,
architectural commit assertions, focused block testbenches, ACT4, synthesis,
and physical-board evidence all have defined roles. It does not yet provide a
scalable constrained-random environment or reusable verification components
for the planned cache, MMU, multicore, heterogeneous ISA, GPU, and NPU work.

Building UVM components directly around today's flat DUT pins would make the
tests, scoreboards, and reference models change whenever the physical bus or
module boundary changes. Conversely, trying to predict one universal future
transaction would mix retirement, translation, coherence, memory, and
accelerator semantics and would become another tightly coupled interface.

## 2. Root cause

The present testbenches combine several concerns that were appropriate for a
small core but scale independently:

- physical signal sampling and driving;
- architectural retirement observation;
- memory state and response generation;
- software workload generation and loading;
- checking, coverage, termination, and reporting.

Future components also introduce concurrency that the current single-order
environment does not need: multiple harts, outstanding memory requests,
multiple retirement lanes, GPU warps, accelerator jobs, translation requests,
and coherence transactions. A FIFO-only comparison model cannot represent all
of those legal partial orders.

## 3. Options considered

1. **Keep extending directed testbenches only.** Lowest immediate cost and
   still valuable for focused invariants, but poor reuse and coverage closure
   as concurrency and protocol count grow.
2. **Build one SoC-specific UVM environment around current pins.** Adds UVM
   quickly, but couples tests and scoreboards to CoreBus and the current
   single-hart hierarchy.
3. **Create one universal transaction for all traffic.** Appears uniform, but
   creates a large optional-field object with unclear ownership and ordering.
4. **Adopt layered domain transactions plus protocol adapters.** Separates
   semantic intent from physical transport and permits incremental block,
   core, and SoC environments. This option is accepted.

## 4. Decision

UVM is an additive verification track. It does not replace directed tests,
ACT4, firmware tests, SVA/formal checks, synthesis/timing evidence, or board
validation.

The stable reuse boundary is a small family of semantic transactions:

| Domain | Initial transaction | Purpose |
|---|---|---|
| Retirement | `retire_event` / `trap_entry_event` | Architecturally completed instruction and its synchronous trap; separate synchronous/asynchronous trap entry |
| Memory | `mem_access` | Addressed read/write request and completion independent of CoreBus/AXI pins |
| Translation | `translation_event` | Virtual-to-physical result, permission, privilege, and fault |
| Coherence | `coherence_event` | Line ownership/state transition, probe, response, and data movement |
| Accelerator | `accel_job` / `accel_completion` | Command, context, operands, completion, and exception |

SystemVerilog `interface` constructs group physical signals, provide modports
and clocking blocks, and host protocol assertions. UVM sequence items and
analysis transactions carry semantic information between reusable components.
Neither abstraction substitutes for the other.

Protocol VIP owns pin timing and protocol legality. Adapters convert between
protocol observations, semantic transactions, and model APIs. Adapters must
not silently become scoreboards or own a second copy of architectural state.

## 5. Concepts adopted from open-source projects

| Project | Adopted concept | Reflection in this architecture |
|---|---|---|
| [OpenTitan DV](https://github.com/lowRISC/opentitan/tree/master/hw/dv) | Reusable DV libraries, typed configurations, generated RAL, machine-readable testplans, thin IP environments | `common/`, generated `ral/`, typed per-agent/per-environment configuration, `testplans/`, `envs/block/` |
| [CORE-V-VERIF](https://github.com/openhwgroup/core-v-verif) | DUT wrapper isolation, RVFI/RVVI architectural observation, reusable core environment | `tb/wrappers/`, `domains/retirement/`, `vip/rvfi/`, `adapters/commit_to_rvfi/`, `envs/core/` |
| [Ibex DV](https://github.com/lowRISC/ibex/tree/master/dv/uvm) | Reactive instruction/data memory agents, one coherent memory view, live ISS comparison | `vip/instruction_memory/`, `models/memory/`, `models/iss/`, ISS adapter and core scoreboard |
| [riscv-dv](https://github.com/chipsalliance/riscv-dv) | Generated programs, target capability files, YAML testlists, reproducible seeds, ISS comparison | `generators/riscv_dv/`, `workloads/`, `testplans/`, regression metadata |
| [NVDLA](https://github.com/nvdla/hw) | Workload/trace reuse, separation of host command, memory, and interrupt paths, functional reference models | Accelerator domain, workload layer, independent command/memory/interrupt agents, pluggable NPU model |
| [CVFPU-UVM](https://github.com/openhwgroup/cvfpu-uvm) | Narrow accelerator agent and C/C++ reference model behind a wrapper | Block-level accelerator environment and model adapter boundary |

GPU-oriented projects also reinforce two rules even when their verification is
not primarily UVM: retain hierarchical execution identity
(`context`/`workgroup`/`warp`/`lane`) and check barriers, fences, forward
progress, starvation, and legal partial order instead of assuming one FIFO.

## 6. Planned directory structure

The structure is introduced incrementally; empty placeholder directories are
not added before a real component exists.

```text
verif/
├── act4/                         existing architecture-test integration
├── uvm/
│   ├── common/                   base config, reset/clock, reporting, utilities
│   ├── domains/
│   │   ├── retirement/           retire_event and architectural coverage
│   │   ├── memory/               protocol-independent memory transactions
│   │   ├── translation/          MMU/TLB events; add only with MMU work
│   │   ├── coherence/            cache/coherence events; add with cache work
│   │   └── accelerator/          GPU/NPU job/completion events
│   ├── vip/                      signal-level agents, monitors, assertions
│   ├── adapters/                 protocol/domain/model translations
│   ├── models/                   memory, ISS, cache, and accelerator models
│   ├── ral/                      generated UVM register models
│   ├── envs/
│   │   ├── block/                divider, LSU, peripheral, cache, MMU, engines
│   │   ├── core/                 CPU plus memory and retirement checking
│   │   └── soc/                  CPUs, shared memory, peripherals, accelerators
│   ├── sequences/
│   │   ├── protocol/             one-agent traffic
│   │   └── virtual/              multi-agent scenarios
│   ├── coverage/                 cross-domain functional coverage
│   ├── tests/                    small policy/configuration selections
│   └── tb/
│       ├── interfaces/           SV interfaces, modports, clocking blocks
│       ├── wrappers/             concrete DUT-to-verification mapping
│       ├── assertions/           protocol, order, deadlock, progress properties
│       └── top/                  static elaboration and UVM launch
├── generators/
│   └── riscv_dv/                 generator target config and integration
├── workloads/                    assembly, C, kernels, tensors, signatures
├── testplans/                    requirements and coverage traceability
├── sim/                          UVM filelists, scripts, manifests, CI entry
└── generated/                    disposable generated tests/RAL/results
```

Agent-local protocol coverage stays with its VIP. `coverage/` contains only
cross-agent or cross-domain coverage. Reference models are replaceable behind
typed adapters so Spike, Sail, or a future commercial model does not determine
the environment's public API.

## 7. Required extensibility invariants

1. Transactions carry identity and ordering fields before concurrency needs
   them: at least `source_id`, `hart_id`, `txn_id`, `epoch`, and `order`; add
   `retire_lane`, `context_id`, `warp_id`, or `lane_id` only in their domain.
2. Scoreboards use associative identity matching and explicit ordering rules
   when traffic may complete out of order. FIFO matching is allowed only where
   the protocol contract guarantees it.
3. One authoritative memory service supplies active responders and expected
   state. The ISS and bus agents must not maintain divergent memories.
4. Configuration objects describe capabilities—width, outstanding depth,
   ordering, coherence, ISA extensions, harts, and lanes—rather than scattering
   preprocessor conditionals through tests.
5. The accepted SoC-map source generates RAL/address collateral; generated
   output is never edited independently.
6. Workloads are independent of simulator and physical bus where practical.
7. SVA/formal owns local safety and progress invariants; UVM owns stimulus,
   end-to-end prediction, coverage, and reporting.
8. No future GPU/NPU/MMU protocol is forced into the existing CoreBus item.
   New transport VIP connects to the relevant semantic domain through an
   adapter.

## 8. First implementation slice

The first slice is deliberately passive and core-level:

```text
commit_pkt_t + trap_entry_t
    -> retirement observation interface + passive monitor
    -> retire_event + trap_entry_event adapters
    -> ordered retirement scoreboard
    -> tohost/result subscriber and retirement coverage
```

### Why this is first

- `commit_pkt_t` and `trap_entry_t` are already stable, registered,
  architecturally meaningful boundaries. The former has an `order` field and
  the latter preserves asynchronous trap entry without falsifying instruction
  commit semantics.
- Passive observation cannot change DUT timing or memory behavior.
- Existing directed programs provide immediate known-good stimulus.
- The slice validates the UVM build, factory/configuration pattern, reporting,
  and regression integration before introducing active agents or an ISS.
- The resulting `retire_event` is reusable by later Spike/Sail adapters,
  riscv-dv programs, multiple harts, and multiple retirement lanes.

### Initial exit gate

- Pin and document the simulator/UVM version supported by the actual toolchain.
- Add only the directories/files required by this slice.
- Define `retire_event` with lossless mapping from the current `commit_pkt_t`
  and `trap_entry_event` with lossless mapping from `trap_entry_t`; include
  `hart_id=0`, `retire_lane=0`, and the existing 64-bit `order` even though the
  current DUT is single-hart/single-retire.
- Implement a clocking-block-based passive retirement observation interface
  and monitor.
- Reproduce existing retirement count/order, trap/write exclusion, and
  committed-`tohost` outcomes for a small smoke subset.
- Demonstrate one deliberately injected scoreboard mismatch is reported as a
  native failing simulator result.
- Run the unchanged focused retirement test and complete directed smoke suite.
- Record compile/runtime overhead and keep the legacy release command green.

The second slice may add a live Spike or Sail adapter. Active reactive memory
agents, riscv-dv, generated RAL, cache/MMU domains, and SoC virtual sequences
follow only after the passive slice is reproducible.

## 9. Consequences and risks

### Positive consequences

- Tests and models depend on semantic contracts rather than today's bus pins.
- Block, core, and SoC verification can grow independently.
- Existing directed workloads become immediate UVM stimulus without rewrite.
- Future physical protocols can be changed by adding VIP/adapters while
  preserving domain scoreboards and coverage.

### Costs and open risks

- UVM introduces build complexity and simulator/version constraints.
- Semantic types require governance; careless field growth can recreate a
  universal transaction.
- Multiple clocks, power/reset domains, coherence, and out-of-order completion
  remain real future design work; directory layering does not solve them by
  itself.
- An ISS may disagree because of configuration, interrupt timing, memory
  visibility, or unsupported custom instructions rather than an RTL defect.
- Generated RAL is useful only if register access policies and side effects are
  represented in the source schema, not merely addresses and widths.

## 10. Verification evidence

This decision is documentation-only. No UVM source, RTL, test, or regression
behavior is implemented by accepting it. Implementation evidence must be added
to this record as each slice closes. Existing `commit_pkt_t`, committed
`tohost`, directed smoke, ACT4, and regression-result negative tests justify
the selected first seam but do not count as UVM verification.

## 11. Learning note

Abstraction is useful when it preserves meaning, not when it merely hides
signals. Keep physical timing in interfaces and protocol VIP, keep
architectural intent in small domain transactions, and make every conversion
explicit at an adapter boundary.
