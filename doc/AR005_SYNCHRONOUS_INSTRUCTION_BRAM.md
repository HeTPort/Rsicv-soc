# AR-005 Synchronous Instruction BRAM

## Result

AR-005 is fixed and verified.

- Program memory now has a one-cycle synchronous request/response contract.
- The accepted request PC is registered beside the RAM response metadata.
- RAW stalls hold both the response word and its PC tag.
- Redirect control discards the single stale response already in flight.
- Vivado 2019.2 maps the default 4Kx32 program memory to four `RAMB36E1`
  primitives.
- The complete directed smoke suite passes 19/19 and the regression utility
  tests pass 4/4.

## Why this change was required

The old `prog_ram` read was combinational. The core sampled the live RAM output
and the current fetch PC into registers on the same edge. That works only while
the memory output follows the current address without a cycle of latency.

A real FPGA Block RAM read is synchronous. If only the RAM process were changed
to a clocked read, nonblocking-assignment timing would make the core register:

```text
current request PC + previous request data
```

That is a valid electrical transaction but an invalid architectural
`{pc,instruction}` pair. It can execute the wrong instruction, and it is
especially dangerous around stalls and redirects.

## Explicit fetch contract

A fetch request is accepted on a rising edge when `instr_ren_o` is high.

| Event | Address/tag state | RAM data state |
|---|---|---|
| Before edge N | request address A is driven | previous response is held |
| Rising edge N | A and request-valid are accepted | `mem[A]` enters the RAM response register |
| After edge N | response PC tag is A | response data is `mem[A]` |
| Rising edge N+1 | IF/ID may capture the response | the next request may be accepted concurrently |

After startup this still sustains one instruction per cycle.

When fetch is stalled, no new request is accepted. Program RAM output and the
response PC/valid metadata both hold, while IF/ID also holds. There is therefore
no opportunity for the instruction word and PC tag to advance independently.

## Implementation

### Program RAM

[`prog_ram.sv`](../src/mem/prog_ram.sv) now uses a clocked RAM read. The actual
memory operation is deliberately simple:

```systemverilog
if (ren_i && fetch_valid)
  mem_rdata_q <= mem[fetch_word_addr];
```

Invalid-address behavior and same-cycle read/write forwarding are not embedded
in that RAM assignment. Their valid/collision flags and forwarded write data
are registered separately, then selected outside the RAM template. This
separation is what lets Vivado recognize the array as Block RAM without losing
the prior observable behavior.

Two Vivado 2019.2 compatibility changes were also necessary:

- use an untyped `FILE` parameter because that synthesizer rejects typed
  SystemVerilog string parameters;
- exclude the simulation-only invalid-write `$error` during synthesis.

### Core response metadata

[`riscv.sv`](../src/core/riscv.sv) no longer registers `instr_rdata_i` a second
time. It registers only the PC and valid tag of an accepted request, while
IF/ID consumes the RAM's already-registered response word directly.

This keeps the request metadata and response data at the same latency and
avoids adding an unnecessary extra fetch stage.

### Redirect and stale-response handling

Branch, JAL, JALR, and `mret` redirects can have one old-path synchronous fetch
response in flight. The existing delayed `fetch_kill_q` discards exactly that
response. A WB trap suppresses a request through `pipe_kill`, then starts the
trap-vector request when the kill releases.

The stale-response count comes from the memory contract: one accepted request
with one-cycle latency means at most one unconsumed old-path response in this
non-pipelined request interface.

## RED/GREEN verification

The RED test was committed separately as `20b8021`. The testbench records an
accepted request address and, on the following half-cycle, checks that the RAM
response equals the word stored at that address.

Against the old combinational RAM, `rv32im` failed immediately:

```text
request_pc=00000000
response=<word at PC+4>
expected=<word at PC>
```

The same assertion passes after the RTL change.

A new directed test,
[`fetch_sync_redirect_test.S`](../testdata/fetch_sync_redirect_test.S), combines:

- a back-to-back RAW dependency that stalls fetch;
- aligned taken branch, JAL, and dependency-fed JALR redirects;
- poison instructions immediately after each redirect;
- a signature proving that each target executes exactly once.

Final behavioral results:

```text
Focused fetch/redirect suite: 5/5 PASS
Complete directed smoke suite: 19/19 PASS
ELF/import utility unit tests:  4/4 PASS
```

Commands:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Tag smoke
python -m unittest test_elf_to_mem.py test_import_act4.py
```

## Vivado 2019.2 evidence

The reproducible check is
[`check_prog_ram_bram.tcl`](../sim/synth/check_prog_ram_bram.tcl). It performs
out-of-context synthesis and fails unless the netlist contains a
`RAMB18E1` or `RAMB36E1`.

The board's exact package and speed grade are not yet recorded, so the script
uses `xc7z010clg400-1` as a provisional Zynq-7010 part. Set the `AR005_PART`
environment variable when the exact board part is known.

Final result:

```text
AR005_PART=xc7z010clg400-1
AR005_BRAM_COUNT=4
AR005_BRAM_CELL=mem_reg_0 REF_NAME=RAMB36E1
AR005_BRAM_CELL=mem_reg_1 REF_NAME=RAMB36E1
AR005_BRAM_CELL=mem_reg_2 REF_NAME=RAMB36E1
AR005_BRAM_CELL=mem_reg_3 REF_NAME=RAMB36E1
AR-005 PASS: prog_ram inferred Block RAM
```

Run it with:

```powershell
Set-Location D:\Rsicv-soc
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -nojournal -nolog `
  -source sim/synth/check_prog_ram_bram.tcl
```

Generated reports and checkpoints are written under `build/vivado_ar005/` and
are intentionally not source-controlled.

## Problems encountered and how they were handled

| Problem | Why it happened | Handling |
|---|---|---|
| Typed `string` parameter stopped synthesis | Vivado 2019.2 does not synthesize that declaration form | Use an equivalent untyped string parameter |
| Simulation `$error` stopped synthesis | The diagnostic was inside synthesizable clocked logic | Guard only the diagnostic with `ifndef SYNTHESIS` |
| Synchronous RAM still became distributed RAM | Output policy was mixed into the RAM read assignment | Register raw RAM data alone and move validity/collision policy outside |
| `ram_style="block"` was reported infeasible | An attribute cannot make an incompatible coding template legal | Keep the attribute as intent, but fix the structure and prove the resulting cells |

## Reusable design principles

1. **Define latency before writing control logic.** Request acceptance,
   response availability, and ownership of each metadata field must be stated
   in clock-edge terms.
2. **Move metadata with the transaction.** A response word is meaningful only
   with the PC, validity, fault, and kill state of the request that produced it.
3. **Keep resource templates mechanical.** Put address policy, error selection,
   forwarding, and protocol decisions around the memory primitive rather than
   inside its canonical inference assignment.
4. **Treat synthesis reports as verification.** Passing simulation proves
   behavior; it does not prove that the FPGA resource or timing model assumed by
   the architecture was implemented.
5. **Derive flush depth from outstanding work.** Count accepted requests that
   may still return after a redirect. Do not choose the number of kill cycles
   by trial and error.

## Remaining Phase 0A work

AR-005 closes the instruction-memory timing item. Phase 0A is not yet complete:
AR-003/AR-004 still require a wait-state-capable data transaction model and a
registered load-response packet that advances and retires exactly once.
