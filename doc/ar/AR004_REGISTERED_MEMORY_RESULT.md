# AR-004 Registered Memory Result and Access-Fault Completion

## Status

**Fixed and verified on 2026-07-29.**

AR-004 builds on the AR-003 single-outstanding LSU transaction model documented
in [`AR003_WAIT_STATE_SAFE_LSU.md`](AR003_WAIT_STATE_SAFE_LSU.md). AR-003 owns a
request until its response and emits one completion event. AR-004 makes the
completed response part of the same registered EX/WB packet as the instruction
that caused it.

The two changes have different responsibilities:

- AR-003 answers, "When has this memory instruction completed exactly once?"
- AR-004 answers, "Which registered instruction owns the returned data or
  error, and what architectural result does it produce?"

## Original problem

After AR-003, the LSU already captured `rsp_rdata` and `rsp_error`. However:

- WB consumed aligned load data directly from the LSU;
- `commit_o.mem_rdata` consumed raw response data directly from the LSU;
- EX/WB carried request metadata but not response data or error state;
- `rsp_error` did not produce a load/store access-fault trap.

The live bus timing dependency was gone, but architectural response ownership
was still split between the EX/WB instruction packet and the LSU's most recent
response registers. That split is fragile: if either stage later advances more
independently, WB or commit can observe a response that belongs to another
instruction.

## Implemented ownership contract

`ex_wb_pkt_t` now carries three memory-result fields:

| Field | Meaning | Consumer |
|---|---|---|
| `mem_rdata` | Raw registered bus response word | Architectural commit record |
| `mem_load_data` | Byte/halfword/word result after alignment and sign/zero extension | WB |
| `mem_error` | Registered response-error status | Trap and side-effect gating |

The existing request fields remain in the same packet:

- `mem_valid`
- `mem_we`
- `mem_addr`
- `mem_wdata`
- `mem_wstrb`
- `mem_info`

At the one-cycle AR-003 `COMPLETE` event, `riscv.sv` assembles request metadata,
raw response data, aligned load data, and error status into one
`ex_wb_pkt_in_safe` value. The `ex2wb` register then captures the complete
instruction result.

```text
accepted request
      |
      v
LSU REQUEST -> RESPONSE -> COMPLETE
                         |
                         | request metadata
                         | raw response
                         | aligned load value
                         | response error
                         v
                 one EX/WB packet
                         |
                    +----+----+
                    |         |
                    v         v
                   WB       commit
```

There is no separate live LSU-to-WB or live LSU-to-commit response path now.

## Access-fault contract

A completed error response remains a valid architectural instruction. It is not
a killed packet and it is not a bubble.

| Operation | `mcause` | `mtval` | GPR write | Store side effect |
|---|---:|---|---|---|
| Failed load | 5, load access fault | Attempted byte address | Suppressed | Not applicable |
| Failed store | 7, store/AMO access fault | Attempted byte address | Suppressed | Target must suppress it |

For both faults:

- `mepc` is the faulting load/store PC;
- the younger instruction is squashed by normal precise-trap control;
- `commit_o.valid=1` and `commit_o.trap=1`;
- `commit_o.mem_valid=1` records that a memory transaction completed;
- request address, direction, masks, and store data remain descriptive;
- a failed load reports `commit_o.mem_rdata=0`;
- `commit_o.rd_we=0`.

Keeping request metadata for the faulting transaction makes the commit record
useful for lockstep checking and debugging. Zeroing failed load data prevents
an invalid target value from being mistaken for an architectural result.

## Implementation

### `src/core/riscv_pkg.sv`

Extended `ex_wb_pkt_t` with `mem_rdata`, `mem_load_data`, and `mem_error`.
Because canonical EX/WB bubbles are the all-zero `EX_WB_PKT_BUBBLE`, the new
fields are automatically harmless on reset, flush, or kill.

### `src/core/execute.sv`

Gives all three result fields deterministic zero defaults for non-memory
instructions and before the LSU completion overlay.

### `src/core/riscv.sv`

- Copies the LSU-held response into the EX/WB packet only during
  `lsu_complete`.
- Converts load/store response errors to causes 5/7.
- Sets `trap_val` to the attempted address.
- Clears register write intent and selects `WB_NONE` on error.
- Includes `mem_error` in the WB trap event.
- Builds `commit_o.mem_rdata` from the EX/WB packet, not the LSU.

### `src/core/wb_stage.sv`

Removed the separate `load_data_i` input. `WB_MEM` now selects
`pkt_wb_i.mem_load_data`, and `mem_error` independently blocks GPR writeback.

### Verification support

- `core_bus_data_ram.sv` can inject an error at one selected address without
  breaking the trap handler's later `tohost` store.
- `run_regression.ps1` and `tests.json` carry that address into the testbench.
- `tb_riscv_core.sv` correlates each committed memory instruction with its
  completed request and response.
- `tb_ar004_packet_contract.sv` directly proves WB consumes packet-owned load
  data and suppresses writeback on packet error.

## RED evidence

RED tests were committed separately as `271a9b2`.

Packet contract:

```powershell
Set-Location D:\Rsicv-soc\sim
vsim -c -do run_ar004_packet.do
```

Before the implementation, compilation failed for exactly the three absent
contract fields:

```text
mem_rdata
mem_load_data
mem_error
```

Architectural fault tests:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Test load_access_fault,store_access_fault
```

Both tests reached failure code 6 and reported `exception=0`: execution
continued after the target returned an error instead of entering the trap
handler.

## GREEN evidence

Focused packet test:

```text
[AR004-PACKET-TB] RESULT: PASS
Errors: 0
```

Focused architectural tests:

```text
rv32im_waitstate    PASS
load_access_fault   PASS
store_access_fault  PASS
All 3 selected tests passed.
```

The unchanged AR-003 protocol test also passes:

```text
[LSU-TB] RESULT: PASS
Errors: 0
```

Complete regression and utilities:

```text
directed smoke: 22/22 passed
Python regression utilities: 4/4 passed
```

Vivado 2019.2 out-of-context synthesis, using the existing AR-003 hierarchy
gate:

```powershell
Set-Location D:\Rsicv-soc\sim\synth
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\check_riscv_soc_ar003.tcl
```

Result:

```text
AR003_PART=xc7z010clg400-1
AR003_BRAM_COUNT=8
AR003_LSU_STATE_CELL_COUNT=2
AR-003 PASS: SoC bus/LSU/RAM hierarchy synthesized
```

Synthesis completed with zero errors. The eight `RAMB36E1` cells are the four
program-memory and four data-memory blocks. This is synthesis/resource
evidence, not timing closure, because the out-of-context check has no clock/XDC
constraint.

## Problems encountered and handling

| Problem | Why it mattered | Handling |
|---|---|---|
| An all-address forced-error target also faults the trap handler's `tohost` store | The test could not report whether the original access fault was correct | Add selected-address error injection; address `0x2000` faults while `0x1000` remains usable for reporting |
| Merely wiring `rsp_error` into trap control would leave load data ownership split | The immediate test could pass while WB/commit still depended on mutable LSU state | Make packet ownership the primary contract, then derive WB, trap, and commit from that packet |
| WSL test-image generation was initially denied by the filesystem sandbox | The `.S` sources could not produce reproducible `.hex` images | Re-run the bounded assembler command with approval and install only the two named images |

## Reusable design principles

1. **A result must travel with its identity.** Data, status, address, masks, and
   destination belong to the instruction that will retire them.
2. **Protocol completion and architectural completion are different
   boundaries.** The LSU captures a bus response; EX/WB turns it into an
   instruction-owned architectural result.
3. **Errors are results, not cancellations.** A failed accepted transaction
   completes exactly once and retires as a precise trap.
4. **One stage should own side-effect authorization.** WB, trap entry, and
   commit should not reconstruct truth from unrelated live signals.
5. **Fault records need an explicit observability policy.** Decide which
   request fields remain visible and which invalid response values are zeroed.
6. **Test error paths without disabling the reporter.** Selective fault
   injection is more useful than making every access fail.
7. **Extend canonical packets, not parallel wires.** All-zero packet bubbles
   make future fields safe by construction.
8. **Preserve the lower-level contract while fixing the next boundary.**
   AR-004 reused AR-003's transaction FSM unchanged and added ownership at its
   completion point.

## Remaining boundary

AR-004 does not implement the SoC address decoder or default unmapped-address
error target. The next data-bus work is to route RAM, timer, UART, GPIO, and a
side-effect-free default error target while preserving this registered result
contract.
