# AR-009 Architectural Memory Topology and Map

## Status

**Accepted on 2026-08-01. Data-RAM/default-target RTL partially implemented by
AR-019 on 2026-08-02.**

This document records the accepted first-milestone memory topology and map for
the FreeRTOS target. Acceptance freezes the hardware/software ABI; it is not a
statement that every RTL, linker, test, or firmware consumer already uses the
map.

Acceptance closes the Phase 1 gate. AR-019 implements the centralized data
decoder, local RAM address, registered default target, and 64 KiB SoC RTL
defaults. The instruction-error path, peripherals, and remaining consumer
migration still implement the rest of the contract.

## Problem

The original SoC had separate physical program and data RAM but no complete
software-visible memory-map implementation:

- every CPU data request was routed directly to the RAM adapter;
- `data_ram` uses only the low RAM-index bits, so unrelated high addresses can
  alias RAM rather than fault;
- the instruction interface has no response-error signal, and an invalid
  program-RAM fetch is represented by an `EBREAK` word rather than instruction
  access-fault cause 1;
- timer, UART, and GPIO files are placeholders;
- current tests use `tohost=0x0000_1000`, which is incompatible with the
  accepted split map;
- the default 4096-word RAM parameters provide 16 KiB per bank, while the
  selected first-milestone capacity is 64 KiB per bank.

A final map must align hardware, linker scripts, firmware headers, test
manifests, image conversion, ACT4 configuration, and FPGA resource use.

## Knowledge required before accepting the map

| Topic | Why it matters in this project |
|---|---|
| Byte addresses versus word indices | The CPU issues byte addresses, while each 32-bit BRAM word represents four bytes. |
| Alignment and little-endian lanes | The LSU already checks byte/halfword/word alignment and constructs store strobes. |
| Single-outstanding bus protocol | Decode and response routing must preserve exactly one response for every accepted request. |
| Synchronous BRAM timing | Instruction and data responses are registered, not combinational reads from the current address. |
| RISC-V fault semantics | Misalignment causes 4/6 are generated before the bus; target errors become causes 5/7; invalid fetches require cause 1. |
| Linker and image layout | `.text` and writable sections must be placed in memories reachable through the corresponding physical ports. |
| RV32 timer atomicity | A 32-bit CPU needs explicit safe sequences for 64-bit `mtime` and `mtimecmp`. |
| FPGA capacity | Address-window sizes must match instantiated word depth and available Block RAM. |

## Current project constraints

1. The CPU has a dedicated synchronous instruction port.
2. Loads and stores use the AR-003 single-outstanding request/response bus.
3. AR-004 carries completed memory data and errors in the registered EX/WB
   packet and converts data response errors into precise access faults.
4. The current physical implementation has distinct `prog_ram` and
   `data_ram` arrays.
5. The first complete system targets one RV32IM hart, M-mode FreeRTOS,
   machine-timer interrupts, polling UART TX, and GPIO.
6. Linux, MMU, caches, DDR, AXI, PLIC, and self-modifying code are outside the
   first milestone.

## Options considered

| Option | Advantages | Costs and risks |
|---|---|---|
| Unified architectural region backed by dual-port BRAM | Simpler linker and ACT4 view; code and data can share capacity | Requires a larger memory refactor, a second data-side program-memory port, collision semantics, and a self-modifying-code policy |
| Split instruction and data architectural regions | Matches the existing two-array Harvard implementation and minimizes near-term RTL change | Requires coordinated split linker/images, data-side placement of constants, and ACT4/tool configuration updates |

## Accepted decision

Use **split architectural instruction and data regions** for the first FreeRTOS
milestone.

Reasons:

- it matches the present physical memory organization;
- it keeps instruction-fetch timing and verified BRAM inference intact;
- it avoids adding dual-port collision and coherency behavior before it is
  required;
- the existing ELF converter already supports separate instruction and data
  images;
- `.rodata`, `.data`, `.bss`, heap, and stacks can all reside in data RAM.

This recommendation deliberately trades a more complex software/linker view
for a smaller and more understandable first hardware implementation.

## Accepted first-milestone map

| Region | Inclusive address range | Size | Permissions | Initial behavior |
|---|---:|---:|---|---|
| Instruction BRAM | `0x0000_0000`–`0x0000_FFFF` | 64 KiB | Read/execute through instruction port | Synchronous fetch; fetch outside this range must become instruction access fault |
| Machine timer/CLINT | `0x0200_0000`–`0x0200_FFFF` | 64 KiB window | Read/write | `mtimecmp=+0x4000`, `mtime=+0xBFF8` |
| UART | `0x1000_0000`–`0x1000_0FFF` | 4 KiB window | Read/write | Polling TX first; invalid offsets return error |
| GPIO | `0x1000_1000`–`0x1000_1FFF` | 4 KiB window | Read/write | Output register and readback; invalid offsets return error |
| Data BRAM | `0x8000_0000`–`0x8000_FFFF` | 64 KiB | Read/write through data port | Holds `.rodata`, `.data`, `.bss`, heap, and stacks |
| Default target | Every other address | — | None | Accept once, perform no write, return one response with `rsp_error=1` |

The timer window is 64 KiB because the standard `mtime` offset `0xBFF8` does
not fit in a 4 KiB window.

### Capacity caveat

The current default RAM depth is 4096 32-bit words:

```text
4096 words × 4 bytes = 16 KiB
```

A 64 KiB bank requires 16,384 words. This capacity is selected for the first
milestone based on the AR-015 comparison and the project owner's 2026-08-01
decision. It must not be described as implemented or physically closed until:

- firmware and FreeRTOS stack/heap estimates justify the sizes;
- `PROG_RAM_DEPTH` and `DATA_RAM_DEPTH` are updated consistently;
- the exact board/part and future peripheral budget are known;
- constrained Vivado implementation confirms timing and final resource margin.

AR-015 now provides the missing early synthesis comparison on the provisional
`xc7z010clg400-1`: two 16 KiB banks use 8/60 RAMB36 tiles (13.33%), while two
64 KiB banks use 32/60 (53.33%). The larger pair fits out-of-context synthesis
and leaves 28 tiles, but this utilization-only result does not decide the
software capacity, peripheral budget, or exact-board questions.

The paired AR-015 post-synthesis timing follow-up also shows that both RAM sizes
have the same failing 87.102 ns combinational MULDIV baseline. Capacity is not
the cause. AR-017 replaces that path with the verified iterative divider and
both capacity profiles pass the refreshed 25/50 MHz OOC checks. Exact-board
timing closure remains required independently of the map choice.

### Simulation completion address

Reserve the final data-RAM word as a simulation-only completion location:

```text
tohost = 0x8000_FFFC
```

The linker must reserve that word so stack, heap, and program sections cannot
overlap it. Existing directed tests and manifests currently using
`0x0000_1000` must be migrated with the Phase 2 decoder and images.

## Access and fault contract

### RAM accesses

- Byte, halfword, and word data accesses are supported.
- Memory is little-endian.
- The LSU generates load/store misalignment causes 4/6 before issuing a
  request.
- Data RAM receives a local address:

```text
local_address = architectural_address - 0x8000_0000
```

- Passing the full high architectural address directly into a small BRAM and
  discarding its upper bits is forbidden.

### Unmapped and rejected data accesses

- An unmapped or invalid-offset request is accepted by a side-effect-free
  default target.
- It receives exactly one response with `rsp_error=1` and zero read data.
- A failed store performs no write.
- The CPU retires the operation as load access fault cause 5 or store access
  fault cause 7 with `mtval` equal to the attempted address.

### Instruction fetches

- Fetches are legal only in the instruction-BRAM range.
- Fetch outside the range must produce instruction access fault cause 1 with
  `mtval` equal to the attempted PC.
- Returning the `EBREAK` encoding for an invalid fetch is not an architectural
  error-reporting mechanism and must be replaced by an explicit instruction
  response-error path.

## Decoder and response-routing contract

The centralized decoder must:

1. compare the complete architectural request address against every region;
2. assert at most one target request-valid signal;
3. subtract the selected target base before indexing local RAM/register space;
4. route unmatched addresses to the default error target;
5. latch the selected target when `req_valid && req_ready` accepts the request;
6. select the later response using that latched target identity, never a live
   request address;
7. prevent a second acceptance while a transaction remains outstanding.

Assertions must prove:

- target selection is one-hot-or-zero before default selection;
- exactly one target accepts each request;
- every accepted request produces exactly one response;
- a response never occurs without an outstanding request;
- an errored write produces no RAM or peripheral side effect;
- back-to-back transactions to different targets remain correctly paired.

## Peripheral rules that must be frozen with implementation

For every MMIO register, document:

- offset, width, and access sizes;
- readable, writable, and hardware-owned bits;
- reset value;
- byte-strobe and partial-write behavior;
- reserved-bit behavior;
- read/write side effects;
- invalid-offset behavior.

For RV32 `mtimecmp`, software should use the safe three-write sequence:

1. write the high word to `0xFFFF_FFFF`;
2. write the low word;
3. write the final high word.

This prevents a transient early timer interrupt while updating two 32-bit
halves.

## One-source-of-truth requirement

AR-014 established [`config/soc_map.json`](../config/soc_map.json) as the
validated machine-readable form of this accepted contract. It produces:

- SystemVerilog decoder constants;
- C-visible firmware headers;
- linker regions and reserved `tohost`;
- normalized simulation data and Vivado Tcl parameters;
- an ACT4-facing map fragment.

During Phase 2, the decoder, testbench/regression, ELF converter, complete
firmware linker, and ACT4/UDB configuration must consume or be mechanically
checked against these generated values. Generation alone does not make those
integrations complete.

Copying unexplained numeric constants into each consumer is not acceptable
because map drift becomes a silent hardware/software ABI bug.

## Verification required before implementation is called complete

1. First and last legal address of every region.
2. Addresses immediately before and after every region.
3. Every RAM byte lane and legal access size.
4. Misaligned load/store requests issue no bus transaction.
5. Unmapped load/store causes 5/7 with the attempted address in `mtval`.
6. Invalid instruction fetch causes 1 rather than breakpoint cause 3.
7. Default-target stores have no side effect.
8. Wait states before acceptance and before response.
9. Back-to-back accesses to different targets.
10. One-hot decode and accepted-request/response/commit accounting.
11. Timer reset, compare crossing, and safe RV32 high/low access.
12. Clean smoke and applicable ACT4 reruns.
13. Vivado BRAM utilization for candidate bank sizes and again after final
    bank sizes and the exact part are selected. The first paired measurement is
    recorded in AR-015.

## Acceptance record

All Phase 1 review questions are answered:

1. [x] Use split architectural instruction/data memory for the first milestone.
2. [x] Use 64 KiB for each instruction/data RAM bank. AR-015 records the
   provisional cost of 32/60 RAMB36 tiles for the pair.
3. [x] Reserve `0x8000_FFFC` as the simulation-only `tohost` word.
4. [x] Data-side access to instruction BRAM is intentionally unsupported.
5. [x] Every invalid peripheral offset returns an access fault.
6. [x] The default target returns one registered error response after one cycle.
7. [x] Use the provisional `xc7z010clg400-1` evidence for planning; require a
   rerun on the exact board part and final post-route resource/timing closure.

## Reusable principles

1. A memory map is a hardware/software ABI, not only a table of addresses.
2. Architectural addresses and physical RAM indices are different layers.
3. Every address has at most one owner.
4. Every accepted request must terminate exactly once.
5. Errors are completed transactions, not hangs or fabricated instructions.
6. Delayed response routing uses transaction-owned registered state.
7. Invalid addresses must not silently alias valid storage or registers.
8. Permissions, access sizes, strobes, reset, and side effects are part of the
   map.
9. Capacity is selected from software evidence and FPGA resources.
10. Boundary and negative tests are as important as normal accesses.
11. One authoritative definition must govern RTL, firmware, linker, tests, and
    compliance tooling.

## Verification evidence

AR-014 generation/check tests validate that the accepted constants are
internally consistent and reproducible across consumer formats. AR-015 uses
those generated profiles to compare 16 KiB and 64 KiB physical RAM cost and
post-synthesis internal timing. That evidence informed the 64 KiB capacity
selection. The project owner's explicit acceptance of every review question
closes the Phase 1 architecture decision. No RTL behavior changed, and the
evidence does not prove Phase 2 implementation.

See [`AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md`](AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md)
for commands, limitations, and preserved raw reports.
See [`AR016_CORE_TO_SOC_ENVIRONMENT_CONTRACT.md`](AR016_CORE_TO_SOC_ENVIRONMENT_CONTRACT.md)
for the complete ownership and transaction boundary from the core through the
SoC and verification environment.
