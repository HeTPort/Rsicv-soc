# AR-014 Machine-Readable SoC Map

## Status

**Configuration infrastructure implemented and verified on 2026-08-01.**

AR-014 did not itself decide AR-009. It makes the accepted
`freertos_split_64k_v1` contract deterministic and consumable by capacity
experiments and future integrations. Current RTL decoding, regression
addresses, and ACT4 execution layout remain unchanged.

The project accepted the complete map on 2026-08-01 after reviewing AR-015 and
answering every AR-009 question. The configuration state is now `accepted`, not
`implemented`.

## Problem

The candidate memory map appeared as repeated prose and numeric constants. A RAM
size or base-address change would require coordinated manual edits to RTL,
firmware, linker scripts, simulation, synthesis, and ACT4 descriptions.
Top-level SystemVerilog parameters alone would make hardware elaboration
flexible but could not keep those non-RTL consumers synchronized.

## Root cause

The project had no explicit owner for the hardware/software address-map ABI:

- RAM modules owned word depths;
- roadmap documents owned proposed byte ranges;
- regressions and ACT4 owned independent `tohost` and depth values;
- no validation rejected overlap, alignment, or stale generated consumers.

## Options considered

### Option A — Continue manual constants

Smallest immediate change, but every new consumer increases silent map-drift
risk.

### Option B — Use only a SystemVerilog package

Centralizes RTL constants but leaves C, GNU ld, Tcl, JSON, and ACT4 values
duplicated.

### Option C — Generate consumers from one validated source

Adds a small generator and generated files, but provides one editable contract,
cross-language output, semantic checks, and a deterministic stale-file gate.

## Decision

Option C is implemented with only the Python standard library:

```text
config/soc_map.json
        |
        v
tools/gen_soc_map.py
        |
        +-- src/generated/soc_mem_map_pkg.sv
        +-- firmware/include/soc_memory_map.h
        +-- firmware/linker/soc_memory.ldh
        +-- sim/generated/soc_map.json
        +-- sim/generated/soc_map.tcl
        +-- sim/generated/soc_ram_utilization_profiles.tcl
        +-- verif/act4/generated_memory_map.yaml
```

JSON was selected instead of YAML because the existing project utilities are
dependency-free. Hexadecimal values remain readable as strings in the source;
the generator normalizes them to the syntax of each consumer language.
The source describes `tohost` by policy as the `last_word` of data RAM, so its
address and width follow capacity/data-width changes without a second edit.

## Function and ownership

| Component | Owns | Must not own |
|---|---|---|
| `config/soc_map.json` | Accepted regions, sizes in bytes, registers, `tohost`, default-target policy, and lifecycle status | RTL behavior or generated syntax |
| `tools/gen_soc_map.py` | Structural/semantic validation and deterministic rendering | Architecture acceptance |
| Generated SystemVerilog package | RTL-readable constants and RAM word-depth derivations | Independent editable values |
| Generated C header/linker fragment | Firmware-visible addresses, capacities, and reserved completion word | Hardware decoding |
| Generated simulation JSON | Normalized data for future regression/converter consumers | Current directed-test migration before Phase 2 integration |
| Generated Tcl | Scalar map parameters plus named capacity profiles for Vivado | Proof of functional decoding |
| Generated ACT4 YAML | Future map integration fragment | Complete UDB configuration or current ACT4 simulation layout |

`riscv_soc` parameters remain the elaboration mechanism. The generated source
is the cross-language configuration mechanism. The isolated synthesis script
passes generated RAM word depths into the existing top-level parameters; it
does not change their checked-in defaults.

## Validation contract

Generation rejects:

- unsupported schemas, widths, names, region kinds, or permissions;
- missing instruction/data RAM regions;
- zero, non-power-of-two, misaligned, overlapping, or out-of-range windows;
- RAM capacities that do not contain complete data words;
- duplicate or out-of-range registers;
- `mtime`/`mtimecmp` definitions that do not fit the timer window;
- a `tohost` that is not the aligned final data-RAM word;
- a default target that fails to report an error or permits a write side effect.

## Acceptance versus implementation boundary

The generated files say `freertos_split_64k_v1 (accepted)`. They must not be
interpreted as proof that:

- 64 KiB per bank fits the final FPGA budget;
- the SoC decodes the accepted bases;
- high unmapped addresses no longer alias RAM;
- invalid instruction fetches generate cause 1;
- current firmware, tests, or ACT4 execute at the accepted addresses.

The final-board budget remains a physical-closure gate. Decode, fault,
firmware, test, and ACT4 migration remain Phase 2 implementation work; they are
not conditions for the already-frozen Phase 1 ABI.

## Utilization-experiment relationship

`sim/synth/check_riscv_soc_configured_ram.tcl` remains the single-contract
capacity entry point. For controlled comparison,
`sim/synth/compare_riscv_soc_ram_utilization.tcl` sources the generated map and
capacity-profile Tcl files, then overrides `PROG_RAM_DEPTH` and
`DATA_RAM_DEPTH` for exactly one named profile per Vivado invocation. Separate
build directories keep the 16 KiB and 64 KiB evidence isolated while
preserving the AR-003 baseline.

The experiment proves only inferred resource cost. Address-map correctness
requires the future decoder and boundary/negative simulations; timing closure
requires a clock constraint and later placement/routing.

## Verification evidence

```powershell
python tools/gen_soc_map.py
python tools/gen_soc_map.py --check
python -m unittest tools/test_gen_soc_map.py
python -m py_compile tools/gen_soc_map.py tools/test_gen_soc_map.py
```

Observed result:

- seven consumer artifacts generated;
- deterministic stale-file check passed;
- generator validation/unit tests: **9/9 passed**, including generated-profile
  derivation and the utilization/timing script relationships;
- existing converter/importer tests: **4/4 passed**;
- Python syntax compilation passed;
- generated SystemVerilog package compiled with ModelSim: **0 errors,
  0 warnings**;
- generated C header parsed with GCC, generated Tcl sourced with `tclsh`, and
  normalized simulation JSON parsed successfully.

The GNU linker fragment is semantically checked by the generator. A native
bare-metal link was not run in this environment: the available MinGW linker
  parsed the script but cannot link its PE unwind relocations into the generated
bare-metal regions, and WSL toolchain access was unavailable. The future
firmware/toolchain phase must parse the fragment with the selected RISC-V GNU
linker before treating it as an active linker input.

The paired Vivado capacity experiment is recorded separately as AR-015 because
it is synthesis evidence, not evidence that the map generator itself is
correct. See
[`AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md`](AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md).

## Consequences

- One edited map can update every supported consumer deterministically.
- Generated files are committed and checked so consumers do not need Python at
  build time.
- Adding a consumer requires one generator renderer and test rather than a new
  hand-maintained map.
- Experimental parameter overrides remain possible but are not automatically
  promoted to the official hardware/software ABI.
- Generator and generated artifacts add review surface; `--check` is therefore
  a required pre-merge gate.

## Reusable principles

1. Parameters configure an instance; a machine-readable source synchronizes a
   system contract.
2. A proposal must carry an explicit state and must not masquerade as
   implemented behavior.
3. Convert byte capacities to word depths at generated or SoC boundaries, not
   by repeating arithmetic in leaf RAMs.
4. Generated files are build products with provenance, not independent sources.
5. Resource inference, functional address decoding, and timing closure require
   separate evidence.
