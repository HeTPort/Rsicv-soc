# AR-016 Core-to-SoC Environment Contract

## Status

**Architecture contract accepted and Phase 1 completed on 2026-08-01.**

The AR-019 centralized data decoder/default target and accepted 64 KiB RTL
defaults were implemented and verified on 2026-08-02. Explicit instruction
access faults and remaining software/peripheral consumers are still open.

This document explains how the RV32IM CPU core connects to the accepted first
FreeRTOS SoC environment. It freezes ownership, address, transaction, error,
software, and verification boundaries. Its data-fabric portion is now
implemented by AR-019; this contract does **not** claim that the instruction
error path or every accepted peripheral/software consumer is implemented.

The authoritative machine-readable ABI is
[`config/soc_map.json`](../config/soc_map.json), configuration
`freertos_split_64k_v1`, state `accepted`.

## 1. Decision summary

The first FreeRTOS milestone uses:

- one RV32IM hart in M-mode;
- architecturally split instruction and data RAM regions;
- 64 KiB instruction BRAM and 64 KiB data BRAM;
- one single-outstanding request/response data bus;
- a centralized SoC address decoder and registered response-source ownership;
- a side-effect-free, one-cycle default error target;
- instruction, load, and store access-fault reporting for rejected accesses;
- a CLINT-compatible machine-timer window, polling UART, and GPIO;
- one generated memory-map source shared by RTL, firmware, linker, simulation,
  synthesis, and ACT4 integration.

The accepted contract prioritizes a small, explicit SoC over AXI, caches, DDR,
or a unified dual-port memory. Those remain future options.

## 2. Architectural boundary

```text
software and test images
        |
        v
linker / ELF converter / BRAM initialization
        |
        v
+------------------------------------------------------------------+
|                         riscv_soc                                |
|                                                                  |
|  clock/reset/loader                                              |
|          |                                                       |
|          v                                                       |
|  +------------------+      instruction request/response          |
|  |   RV32IM core    |----------------------------------+         |
|  |                  |                                  v         |
|  | IF / pipeline    |                         instruction BRAM    |
|  | EX / CSR / trap  |                                            |
|  | LSU              |-- core data request --> SoC decoder        |
|  +------------------+                         |  |  |  |  |       |
|          ^                                    |  |  |  |  +default
|          |                                    |  |  |  +----GPIO |
|          +--------- selected response --------+  |  +-------UART |
|                                                  +----------timer|
|                                                  +-------data RAM|
+------------------------------------------------------------------+
        |
        +--> architectural commit record --> testbench / scoreboard
```

The CPU core is an initiator. Memories and peripherals are SoC targets. The
core does not own physical base addresses, peripheral register maps, RAM
instances, or response multiplexing.

## 3. Ownership rules

| Layer | Owns | Must not own |
|---|---|---|
| CPU front end | Requested PC, synchronous fetch timing, response/PC pairing, redirect kills | Program-RAM depth, physical base decode, invalid-address substitution |
| Pipeline/execute | ISA semantics, branch/jump targets, CSR/trap ordering, architectural validity | Peripheral selection or MMIO behavior |
| LSU | Alignment checks, request payload stability, one outstanding data transaction, load extension, access-fault conversion | SoC address aliases, target-specific latency, peripheral registers |
| SoC decoder/fabric | Full-address decode, target request routing, local-address subtraction, accepted-target registration, response selection | Re-decoding a live address after acceptance |
| RAM/peripheral target | Local offsets, storage/register behavior, strobes, reset values, target errors | Architectural trap entry or pipeline control |
| Default target | Terminate every unmapped/invalid request once with an error and no side effect | Silent aliasing, hangs, or writes |
| Firmware/tooling | Sections, symbols, stack/heap, drivers, generated constants | Independent copied map constants |
| Verification environment | Image loading, commit checking, protocol assertions, `tohost` completion | Replacing architectural error behavior with log-only heuristics |

## 4. Accepted software-visible map

All addresses are byte addresses. A 32-bit word contains four little-endian byte
lanes.

| Region | Inclusive range | Size | Access |
|---|---:|---:|---|
| Instruction BRAM | `0x0000_0000`–`0x0000_FFFF` | 64 KiB | Instruction fetch only, read/execute |
| Machine timer | `0x0200_0000`–`0x0200_FFFF` | 64 KiB window | Data-bus read/write |
| UART | `0x1000_0000`–`0x1000_0FFF` | 4 KiB window | Data-bus read/write |
| GPIO | `0x1000_1000`–`0x1000_1FFF` | 4 KiB window | Data-bus read/write |
| Data BRAM | `0x8000_0000`–`0x8000_FFFF` | 64 KiB | Data-bus read/write |
| Default target | Every other address | — | Error completion only |

Accepted special addresses:

- `mtimecmp = 0x0200_4000`, 64 bits;
- `mtime = 0x0200_BFF8`, 64 bits;
- simulation-only `tohost = 0x8000_FFFC`.

Data-side access to instruction BRAM is intentionally unsupported in this
milestone. The linker places `.text` in instruction BRAM and `.rodata`,
`.data`, `.bss`, heap, and stacks in data BRAM. Self-modifying code is outside
scope.

## 5. Instruction path

### Accepted behavior

1. The core issues a fetch request with a byte-addressed PC.
2. The SoC validates the complete PC against the instruction-BRAM range.
3. For a legal PC, the SoC subtracts `0x0000_0000`, reads synchronous BRAM, and
   returns the instruction with the corresponding request PC.
4. A fetch outside the accepted range returns an explicit instruction response
   error.
5. The core converts that error into instruction access fault cause 1 with
   `mtval` equal to the attempted PC.
6. A redirect or trap kills any stale synchronous response already in flight.

Returning an `EBREAK` instruction for an invalid address is forbidden because
it changes an access fault into breakpoint cause 3.

### Current implementation gap

The current core instruction interface carries request/address/data but no
response-error signal. `riscv_soc` also connects it directly to `prog_ram`.
Phase 2 must add an explicit error path and range checking without disturbing
the verified one-cycle fetch response/PC pairing.

## 6. Data request/response lifecycle

The core bus supports one outstanding transaction.

```text
IDLE -> REQUEST -> RESPONSE -> COMPLETE -> IDLE
```

1. The LSU checks byte/halfword/word alignment before issuing a request.
2. The LSU presents `req_valid`, `addr`, `write`, `size`, `wdata`, and `wstrb`.
3. While `req_ready` is low, every request field remains stable.
4. `req_valid && req_ready` accepts the request exactly once.
5. The SoC records the selected target at acceptance.
6. The target may respond later with `rsp_valid`, `rdata`, and `error`.
7. The response mux uses the recorded target, never the current request address.
8. The LSU registers the result and releases exactly one EX/WB completion.

The pipeline holds the owning ID/EX packet while the LSU is busy. A request is
not replayed, a response is not duplicated, and a younger instruction cannot
retire ahead of the held memory operation.

## 7. Decode and local addressing

The AR-019 data decoder compares the full 32-bit architectural address. After a
target is selected, it supplies a target-local byte address; the data-RAM rule
is implemented now and the peripheral rules apply when those targets are added:

```text
data_ram_local = architectural_address - 0x8000_0000
timer_local    = architectural_address - 0x0200_0000
uart_local     = architectural_address - 0x1000_0000
gpio_local     = architectural_address - 0x1000_1000
```

Passing a high architectural address directly to a small memory and discarding
upper bits is forbidden because it creates silent aliases.

Before default selection, target request enables must be one-hot-or-zero. After
default selection, exactly one target accepts each legal bus request.

## 8. Error and trap mapping

| Condition | Owner before trap | Architectural result |
|---|---|---|
| Misaligned instruction target | Core execute stage | Cause 0, target in `mtval` |
| Fetch outside instruction region | SoC fetch range/error path | Cause 1, PC in `mtval` |
| Misaligned load | LSU before request | Cause 4, address in `mtval` |
| Unmapped/rejected load | Target/default response error | Cause 5, address in `mtval` |
| Misaligned store | LSU before request | Cause 6, address in `mtval` |
| Unmapped/rejected store | Target/default response error | Cause 7, address in `mtval`, no write |

Every invalid peripheral offset returns an access error. The accepted default
target has one registered response cycle, returns zero data with `error=1`, and
never performs a write. Errors are completed transactions, not timeouts.

## 9. Reset, loading, and boot

The present simulation-oriented wrapper provides a program-RAM write port and
holds the CPU in reset until `load_done`:

```text
cpu_reset_n = external_reset_n && load_done
```

The Phase 2 integration must preserve deterministic startup while separating:

- external clock/reset and board synchronization;
- program/data image initialization;
- CPU reset release;
- peripheral reset values;
- software-visible memory contents.

RAM reset must not be added in a way that prevents Block RAM inference. Timer,
UART, GPIO, fabric ownership state, and outstanding-transaction state require
defined reset behavior.

## 10. Software and generated-contract flow

```text
config/soc_map.json (accepted)
        |
        v
tools/gen_soc_map.py
        |
        +--> SystemVerilog package
        +--> C header
        +--> GNU linker fragment
        +--> simulation JSON/Tcl
        +--> Vivado RAM profiles
        +--> ACT4-facing YAML fragment
```

Generated files are authoritative syntax translations, not independent edit
points. Phase 2 and firmware integration must consume them or mechanically
check their constants. The configuration state `accepted` means the ABI is
frozen; it does not mean every consumer already implements it.

## 11. Verification environments

### Core-level verification

`tb_riscv_core` may continue to test pipeline, CSR, trap, LSU, and architectural
commit behavior with controlled memory models. It does not prove SoC decode.

### SoC-level verification

`tb_riscv_soc` provides the AR-018 environment for unmapped load/store and
invalid-fetch behavior. The data cases are GREEN through AR-019; invalid fetch
remains RED. This environment must grow into the complete
integration environment for:

- every region boundary and the addresses immediately outside it;
- base subtraction and no high-address aliasing;
- RAM byte lanes and legal access sizes;
- unmapped data and invalid peripheral offsets;
- invalid instruction fetch cause 1;
- wait states and back-to-back requests to different targets;
- one-hot decode and exactly-one acceptance/response/commit;
- `tohost` reservation and completion;
- timer/UART/GPIO register behavior as each target is implemented.

The architectural `commit_o` record remains the verification boundary for
retirement. Native simulator exit status plus transcript checks remain the
regression boundary for infrastructure success.

## 12. Current, accepted, and implemented states

| State | Meaning now |
|---|---|
| Current RTL | Direct instruction RAM with paired fetch-error status; centralized data fabric to 64 KiB-default RAM or registered error target |
| Accepted Phase 1 ABI | Split 64 KiB map, addresses, visibility, errors, default-target latency, generated definitions |
| Phase 2 result | Complete: data fabric/default target plus precise data and instruction access faults |
| Later SoC phases | Timer interrupt, UART/GPIO, firmware, FreeRTOS, exact-board closure |

## 13. Phase 2 implementation order

1. Include the accepted generated SystemVerilog package in all RTL/synthesis
   file lists.
2. Add a centralized data decoder and side-effect-free default target.
3. Latch response-source identity at request acceptance.
4. Apply local-address subtraction at each target boundary.
5. Add instruction range/error signaling and cause-1 handling.
6. Promote the accepted 16,384-word RAM depths in the SoC configuration.
7. Migrate linker, images, `tohost`, regression manifests, converter, and ACT4
   descriptions together.
8. Turn the AR-018 negative RED cases GREEN, then add SoC-level boundary,
   wait-state, and cross-target tests.
9. Rerun functional regression and exact-part synthesis/timing evidence.

AR-019 completes steps 1-4 and 6 for the data path, makes the AR-018 data cases
GREEN, adds initial boundary/back-pressure/cross-target coverage, and reruns
functional plus provisional-part OOC synthesis. AR-018 later completes step 5
and the fetch case in step 8. Step 7 continues with firmware/tool consumers in
their owning later phases; real peripheral targets and exact-board closure also
remain later-phase work rather than Phase 2 exit conditions.

## 14. Consequences and risks

- The split map preserves the verified two-array Harvard implementation and
  avoids dual-port coherency work.
- Software and compliance tools must deliberately split executable and writable
  sections.
- Two 64 KiB banks use 32/60 RAMB36 tiles on provisional
  `xc7z010clg400-1`; exact-board and final-peripheral margin remain open.
- AR-015 shows RAM capacity is not the timing bottleneck. AR-017 replaces its
  87.102 ns combinational-divider baseline with a verified iterative divider;
  both profiles now pass 25/50 MHz OOC STA, while physical closure remains open.
- The accepted ABI should change only through a new reviewed decision and
  regenerated artifacts, never through isolated constants.
- AR-019 records the implemented decoder/default-target choices and evidence in
  [`AR019_CENTRALIZED_DATA_FABRIC.md`](AR019_CENTRALIZED_DATA_FABRIC.md).

## 15. Reusable principles

1. A core issues architectural requests; the SoC owns physical targets.
2. Address ownership is decided from the complete address before local indexing.
3. Delayed response routing requires transaction-owned registered identity.
4. Every accepted request terminates exactly once, including errors.
5. Contract acceptance, RTL implementation, and physical closure are separate
   states and must never be conflated.
6. One machine-readable ABI should drive every hardware and software consumer.
