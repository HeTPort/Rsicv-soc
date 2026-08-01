# Memory-Map and Core-Bus Contract Design Guide

## Two contracts, not one

A memory-map contract and a bus protocol are related but distinct:

- the **memory map** assigns byte-address ranges and software-visible behavior
  to memories and peripherals;
- the **bus contract** defines request acceptance, response completion,
  back-pressure, and errors.

Writing only a table of base addresses is insufficient. RTL, linker scripts,
firmware headers, testbenches, image converters, and verification tools must
agree on both contracts.

## Recommended design process

### 1. Start from software-visible requirements

Inventory every required target before choosing addresses:

- executable storage;
- writable data, stack, heap, and `.bss`;
- machine timer;
- polling UART;
- GPIO;
- test-only completion/signature locations;
- an explicit unmapped-address error target.

Record required capacity from ELF size reports and expected stacks/heaps rather
than choosing RAM sizes only by intuition.

### 2. Decide the physical and architectural memory topology

The CPU can have separate instruction and data ports without requiring separate
architectural address regions. For this repository, Phase 1 must explicitly
choose between:

- one architecturally unified region backed by dual-port BRAM; or
- architecturally split instruction and data regions.

The first option simplifies the linker, ACT4, and capacity use. The second
matches the current two-array RTL more closely but requires coordinated split
linker/image/tool descriptions. This decision must precede final addresses.

### 3. Define regions in byte units

For every region specify:

| Property | Required decision |
|---|---|
| Base and size | Byte address, byte capacity, alignment |
| Ownership | Exactly one target for every mapped address |
| Permissions | Read, write, execute |
| Access widths | Byte, halfword, word; any prohibited sizes |
| Byte lanes | Little-endian mapping and `wstrb` behavior |
| Alignment | Allowed addresses and misalignment fault behavior |
| Latency | Fixed or variable; never assumed by software |
| Side effects | Read-clear, write-one-to-clear, FIFO pop, etc. |
| Reset value | Memory/register state after reset |
| Error behavior | Unmapped, read-only write, invalid offset |

Prefer naturally aligned, non-overlapping, power-of-two decode windows when
practical. Reserve unused offsets for future compatibility rather than
silently aliasing them.

### 4. Define one transaction lifecycle

The initial core bus should support one outstanding transaction:

```text
req_valid, req_ready, req_addr, req_write, req_wdata, req_wstrb
rsp_valid, rsp_rdata, rsp_error
```

Required invariants:

1. A request is accepted exactly on `req_valid && req_ready`.
2. Request fields remain stable while waiting for acceptance.
3. An accepted request is issued exactly once.
4. Every accepted request receives exactly one response.
5. A response cannot occur without an outstanding request.
6. Loads and stores retire only after their response.
7. An accepted transaction is not cancelled by a later interrupt.
8. No second request is accepted while one is outstanding.

These rules make zero-wait RAM and delayed peripherals interchangeable without
changing CPU semantics.

### 5. Make errors complete normally

Unmapped or rejected accesses must not hang. A default target should accept the
request and return `rsp_error` without a write side effect. The CPU converts
that response into a load/store access-fault trap.

An error is therefore a completed transaction with fault status, not the
absence of a response.

### 6. Latch routing at acceptance

The address decoder must remember which target accepted the request. Response
selection cannot use a later live address because the pipeline may already be
holding or presenting different values.

Only one target may see an accepted request. Assertions should prove one-hot
selection and prevent simultaneous RAM/peripheral writes.

### 7. Define peripheral register semantics precisely

For every register document:

- offset and width;
- readable/writable bits;
- reset value;
- effects of partial writes and byte strobes;
- reserved-bit behavior;
- read/write side effects;
- hardware-owned versus software-owned bits;
- atomicity requirements.

The 64-bit `mtime` and `mtimecmp` registers require an explicit safe RV32
high/low access sequence. The timer window must be large enough for standard
offsets `0x4000` and `0xBFF8`; a 4 KiB CLINT window is insufficient.

### 8. Treat the map as an ABI

Once firmware depends on an address or register behavior, changing it is an ABI
change. Keep reserved space, version changes deliberately, and avoid using
undocumented aliases.

Maintain one authoritative set of constants and generate or mechanically check:

- SystemVerilog decode constants;
- C headers;
- linker scripts;
- testbench ranges;
- ELF/image conversion configuration;
- ACT4/Sail/UDB descriptions.

### 9. Verify the contract, not only devices

Minimum directed tests should cover:

- every legal RAM access size and byte lane;
- wait states before request acceptance and before response;
- back-to-back accesses to different targets;
- unmapped and invalid-offset accesses;
- read-only writes and partial peripheral writes;
- exactly-one request/response/commit behavior;
- reset values;
- no side effect on an errored write;
- interrupt arrival during an outstanding transaction.

Protocol assertions should remain active in all regressions.

## Current provisional map

The roadmap currently proposes:

| Region | Base | Required window |
|---|---:|---:|
| Instruction BRAM | `0x0000_0000` | 64 KiB |
| Machine timer/CLINT | `0x0200_0000` | At least 64 KiB |
| UART | `0x1000_0000` | 4 KiB |
| GPIO | `0x1000_1000` | 4 KiB |
| Data BRAM | `0x8000_0000` | 64 KiB |

The detailed split-memory recommendation, access/error contract, capacity
caveat, verification plan, and open review questions are recorded in
[`AR009_ARCHITECTURAL_MEMORY_MAP.md`](AR009_ARCHITECTURAL_MEMORY_MAP.md).
AR-009 remains proposed until those questions are reviewed; the table above is
not yet an implemented ABI.

The physical capacity tradeoff is now measured separately in
[`AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md`](AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md).
On provisional `xc7z010clg400-1`, the two 16 KiB banks use 8/60 RAMB36 tiles
and the two 64 KiB banks use 32/60. This informs, but does not replace, the
software-capacity and exact-board decisions. Paired post-synthesis timing also
shows the same failing 87.102 ns combinational MULDIV path for both capacities,
so the present critical-path problem is independent of the memory-map choice.

This table is not frozen. The unified-versus-split BRAM decision must first be
reconciled with ACT4, the linker, image generation, BRAM capacity, and Vivado
inference. No Phase 2 RTL should embed these provisional addresses before that
decision is recorded.

## Exit criteria for freezing Phase 1

The contract is ready for RTL only when:

- every address belongs to at most one target;
- every request terminates with exactly one response or error;
- the memory topology decision is recorded;
- linker, C, RTL, tests, and ACT4 use consistent byte ranges;
- access faults and partial writes are defined;
- timer atomicity and window size are defined;
- the handshake can explain stalls without duplicate requests or commits;
- a review can answer what happens for every address, access size, and error.

## Machine-readable configuration boundary

The proposed map is now represented by
[`config/soc_map.json`](../config/soc_map.json) and validated/generated by
[`tools/gen_soc_map.py`](../tools/gen_soc_map.py). The generated SystemVerilog,
C, linker, simulation, Tcl, and ACT4-facing files eliminate manual numeric
duplication, but they do not accept the map or implement address decoding.

Keep the responsibilities separate:

```text
machine-readable map = cross-language architectural proposal
RTL parameters       = elaboration settings for one hardware instance
address decoder      = implemented ownership and local-address translation
Vivado report        = physical resource evidence for one configuration
```

The complete ownership table, validation contract, and generation commands are
recorded in [`AR014_MACHINE_READABLE_SOC_MAP.md`](AR014_MACHINE_READABLE_SOC_MAP.md)
and [`config/README.md`](../config/README.md).
