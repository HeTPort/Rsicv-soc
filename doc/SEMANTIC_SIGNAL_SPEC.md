# Semantic Signal and Interface Specification

**Status:** Phase 4 normative design specification

**Scope:** CPU pipeline, retirement, CSR state, redirects, the CPU-local data
bus, and polling UART TX/RX

**Last updated:** 2026-08-09

This document defines what important signals mean, who owns them, when they are
valid, and how future signals must be named and grouped. It complements the
implementation-oriented project knowledge base and the historical architecture
decision record.

## 1. Why semantic definitions are required

A signal name describes a value; a semantic contract also describes time,
ownership, and consequences. For example, `trap` is ambiguous unless the
design states whether it means:

- an exception candidate detected in EX;
- an architectural trap entry selected at retirement;
- a one-cycle CSR state-update command; or
- an observation reported to a testbench.

Those signals may carry related information, but they are not interchangeable.
The project therefore follows this rule:

> Signals are grouped by shared meaning, owner, validity, and lifetime—not
> merely because they are adjacent wires or belong to the same module.

## 2. Normative vocabulary

| Term | Definition |
|---|---|
| Candidate | A computed possibility that has not yet been selected architecturally. |
| Intent | An instruction-carried request for a future effect; it may still be suppressed. |
| Effective value | A value after architectural filtering such as WARL handling or hardware-owned-bit composition. |
| Command | A selected one-cycle request to the sole owner of architectural state. |
| State/view | A persistent value or a combinational projection of persistent state. |
| Event | A one-cycle occurrence. Events are not persistent pending levels. |
| Level | A condition that remains asserted while its condition is true, such as MTIP. |
| Observation | Verification/debug information that must not control architectural behavior. |
| Bubble | A canonical all-zero invalid pipeline packet; it represents no instruction. |
| Faulting instruction | A valid instruction that reports a synchronous trap but has no normal side effects. |
| Killed instruction | A younger instruction converted to a bubble because an older event won. |

## 3. Ownership rules

Every architectural effect has exactly one state owner.

| State or effect | Sole owner | Producers may provide |
|---|---|---|
| Integer register state | `regfile.sv` | `rf_write_cmd_t` |
| Machine CSR state and counters | `csr_regfile.sv` | `csr_retire_cmd_t`, hardware interrupt levels |
| Architectural retirement selection | `retire_stage.sv` | `ex_wb_pkt_t`, CSR preview context, interrupt level |
| PC and pipeline movement | `core_ctrl.sv` plus `pc_counter.sv` | typed redirect candidates and wait/kill conditions |
| LSU transaction state | `lsu.sv` | ID/EX memory intent and bus handshakes |
| Fabric response ownership | `soc_data_fabric.sv` | accepted-target identity |
| Timer state | `mtime_timer.sv` | accepted core-bus writes and clock ticks |
| UART TX queued byte | `core_bus_uart.sv` | accepted legal TXDATA write or shifter transfer |
| UART TX active frame/timing | `uart_tx.sv` | accepted byte transfer and baud counter |
| UART RX synchronization/frame timing | `uart_rx.sv` | asynchronous pin samples and baud counter |
| UART RX FIFO/error state | `core_bus_uart.sv` | receiver byte/error events and accepted MMIO reads/W1C writes |

A producer must not directly mutate state owned by another module. It emits an
intent, candidate, command, or protocol transfer instead.

## 4. Naming standard

### 4.1 Port suffixes

| Suffix | Meaning |
|---|---|
| `_i` | Input to the module. |
| `_o` | Output from the module. |
| `_io` | Bidirectional electrical signal only; do not use for logical request/response protocols. |

### 4.2 Time and role suffixes

| Suffix | Meaning |
|---|---|
| `_q` | Registered state owned by the declaring module. |
| `_d` | Explicit next value for a corresponding `_q` register. |
| `_req` | Request payload or intent; not proof that it was accepted. |
| `_cmd` | Selected one-cycle state-changing command. |
| `_ctx` / `_context` | Read-only semantic view used for a decision. |
| `_candidate` | Unselected computed alternative. |
| `_event` | One-cycle occurrence. |
| `_pending` | Persistent level condition, never an unqualified one-cycle pulse. |
| `_effective` | Architecturally filtered/composed value. |
| `_raw` | Unfiltered source value; use only when both raw and effective values exist. |
| `_safe` | Side effects have been suppressed according to the stated kill/trap rule. |

Avoid vague names such as `control`, `status`, `done`, `enable`, or `data`
without a domain qualifier. Prefer `div_complete`, `irq_eligible`,
`retire_redirect`, and `csr_write_effective`.

### 4.3 Active polarity

- Active-low reset uses `rst_ni`.
- Other logical controls are active high unless the name ends in `_n` and the
  interface contract explicitly defines active-low behavior.
- Do not encode transient timing in names such as `delayed2`; use a semantic
  name plus `_q`, or document an intentional pipeline stage.

## 5. Packed type standard

Create a packed struct when all fields:

1. share one semantic operation or one instruction;
2. advance, hold, or become invalid together;
3. have the same producer/consumer direction; and
4. benefit from a canonical zero/default value.

Do not create a packed struct merely to reduce the apparent number of ports.
Do not combine `valid` and `ready` into the same unidirectional payload because
they have different owners.

### 5.1 Pipeline packets

Pipeline packets carry information belonging to one instruction. Their
`valid` field is authoritative. Every invalid registered packet must equal its
canonical all-zero bubble.

| Current type | Current definition | Phase 3 evolution |
|---|---|---|
| `fetch_pkt_t` | Fetch response validity, error, PC, instruction bits. | No semantic change. |
| `id_ex_pkt_t` | Decoded operands and RF/EX/memory/CSR intent; MRET/WFI markers. | No ownership change. |
| `ex_wb_pkt_t` | Executed instruction, results, memory completion, synchronous trap metadata, MRET marker. | Add resolved `next_pc` and WFI marker so retirement has complete instruction semantics. |
| `commit_pkt_t` | Ordered verification observation for a valid EX/WB instruction. | Remains observational; asynchronous trap entry is reported separately if needed rather than fabricated as a synchronous instruction trap. |

### 5.2 Retirement types

The following types are the normative Phase 3 contract.

```systemverilog
typedef struct packed {
  logic             valid;
  logic [4:0]       addr;
  logic [DW-1:0]    data;
} rf_write_cmd_t;

typedef struct packed {
  logic             valid;
  logic [11:0]      addr;
  logic [DW-1:0]    wdata;
} csr_write_req_t;

typedef struct packed {
  logic [DW-1:0]    mstatus;
  logic [DW-1:0]    mie;
  logic [DW-1:0]    mip;
  logic [AW-1:0]    mtvec;
} csr_irq_context_t;

typedef struct packed {
  logic             valid;
  logic             interrupt;
  logic [AW-1:0]    pc;
  logic [DW-1:0]    cause;
  logic [DW-1:0]    tval;
} trap_entry_t;

typedef struct packed {
  logic             valid;
  logic [AW-1:0]    pc;
  redirect_reason_e reason;
} redirect_t;

typedef struct packed {
  csr_write_req_t   csr_write;
  trap_entry_t      trap;
  logic             mret;
  logic             instret;
} csr_retire_cmd_t;
```

`csr_retire_cmd_t` is deliberately not a mutually exclusive enum. An ordinary
CSR write and an asynchronous trap entry may both be valid at the same
retirement boundary.

### 5.3 CSR context versus complete CSR state

Do not expose all CSR storage in a monolithic `csr_state_t` simply for visual
symmetry. Consumers receive the smallest stable view they require:

- EX uses the addressed CSR read port and the current/bypassed MEPC target.
- Retirement uses `csr_irq_context_t`.
- Verification may use dedicated observation signals when justified.

`csr_irq_context_t` contains `mtvec` because interrupt selection consumes the
vector in the same decision, but only `mstatus`, `mie`, and `mip` participate
in eligibility. `mepc` is excluded because trap entry writes it and MRET reads
it through a different semantic path.

## 6. Retirement semantics

### 6.1 Safe boundary

An ordinary interrupt may be selected only when a valid instruction completes
the retirement boundary and no synchronous exception or MRET owns that
boundary. A waiting WFI supplies a second safe boundary using its saved resume
PC. An accepted LSU transaction or running divider completes before interrupt
selection because its owning instruction has not yet reached retirement.

### 6.2 Synchronous exception ordering

For a synchronous exception:

- the faulting packet remains valid for trap reporting;
- RF, CSR, store, normal redirect, and `instret` effects are suppressed;
- trap entry uses the faulting PC and synchronous cause/tval; and
- younger state is killed.

### 6.3 Interrupt ordering

For an interrupt after a normally retired instruction:

1. derive the instruction's raw CSR write intent independently of IRQ choice;
2. apply CSR WARL and hardware-pending composition to create the effective
   post-retirement IRQ context;
3. compute eligibility from that context;
4. if eligible, allow the normal RF/CSR effects and `instret` increment;
5. then apply trap entry, saving `next_pc` to `mepc`; and
6. kill all younger instructions.

This makes a CSR write and interrupt entry simultaneous commands with defined
internal ordering, not mutually exclusive alternatives.

### 6.4 MRET boundary

MRET is decoded and carried through EX, but its architectural redirect and
`mstatus` restoration are both selected by `retire_stage`. Interrupt selection
is suppressed on the same MRET retirement boundary and reevaluated at the next
safe boundary. This keeps the privilege-state transition and redirect under
one owner and avoids two architectural redirects claiming one cycle.

### 6.5 WFI boundary

WFI retires once, increments `minstret` once, and records `next_pc`. If no
interrupt is eligible, the core enters a logical wait state with no live WFI
packet. A later eligible interrupt exits wait and uses the saved PC. Physical
clock gating is a later implementation layer and must not change these
architectural semantics.

## 7. CSR effective-state standard

The CSR register file owns WARL policy and hardware-composed fields. Retirement
may request a preview, but must not duplicate the filtering rules.

The IRQ context is constructed as follows:

```text
context = current architectural CSR view
if a normal retiring CSR write exists:
    overlay the addressed field with its WARL-effective value
compose hardware-owned pending bits, including MTIP
eligible = context.mstatus.MIE && context.mie.MTIE && context.mip.MTIP
vector   = context.mtvec
```

MTIP is a hardware-owned level. An ordinary CSR write cannot manufacture or
clear it. Timer deassertion is caused by changing `mtimecmp` so the comparison
is false, not by clearing a latched interrupt pulse in the CPU.

## 8. Redirect standard

Every redirect carries a valid bit, target PC, and semantic reason. Current and
future producers are:

| Producer | Reasons |
|---|---|
| `execute.sv` | Taken branch, JAL, and JALR candidates. |
| `retire_stage.sv` | MRET, synchronous exception, and asynchronous interrupt. |

`core_ctrl.sv` owns selection and movement. An older retirement redirect has
priority over a younger EX redirect. Selecting a redirect must also define the
corresponding immediate and delayed fetch kills for synchronous instruction
memory.

## 9. Core-bus standard

The bus is a single-outstanding request/response protocol:

```text
request transfer = req_valid && req_ready
response transfer/observation = rsp_valid
```

Payloads are packed:

- `core_bus_req_t`: address, read/write direction, size, write data, strobes;
- `core_bus_rsp_t`: read data and error.

Handshake signals remain explicit. A target must:

- accept a request exactly once;
- return exactly one response;
- hold side-effecting request interpretation to the accepted payload;
- return a registered response unless a more general future protocol is
  explicitly adopted; and
- avoid side effects for unsupported or erroneous accesses.

The fabric decodes the full architectural address once, translates only the
selected target's local address, and registers the response owner until the
response arrives.

## 10. Timer signal semantics

| Signal/value | Semantic definition |
|---|---|
| `mtime` | Free-running 64-bit SoC time counter; increments according to the documented timer tick parameter. |
| `mtimecmp` | 64-bit comparison threshold, accessed as two RV32 words. |
| `irq_mti` | Level: `mtime >= mtimecmp`; not a one-cycle pulse and not a sticky latch. |
| Timer local address `0x4000` | Low word of `mtimecmp`; `0x4004` is the high word. |
| Timer local address `0xBFF8` | Low word of `mtime`; `0xBFFC` is the high word. |

The timer is a normal `core_bus_req_t`/`core_bus_rsp_t` target. Full SoC
addresses are decoded and base-subtracted by the fabric; the timer itself sees
only local offsets.

RV32 software avoids transient early interrupts while replacing `mtimecmp` by
writing the low word to all ones, then the high word, then the final low word.
The hardware provides ordinary word writes; it must not invent a hidden
multiword transaction that the bus cannot represent.

## 11. UART TX/RX signal semantics

| Signal/value | Semantic definition |
|---|---|
| `uart_tx_o` | Physical 8N1 serial level: high while idle, low start bit, eight LSB-first data bits, high stop bit. |
| `tx_ready_o` | Level: the holding stage can accept a byte now, including simultaneous dequeue/enqueue. |
| `tx_busy_o` | Level: the holding stage or active shifter owns at least one byte. |
| `shifter_valid` | The holding register owns a byte offered to the shifter; not proof of transfer. |
| `shifter_ready` | The shifter can accept a new frame in the current cycle. |
| `dequeue` | Event: `shifter_valid && shifter_ready`; ownership moves from holding register to shifter. |
| `enqueue` | Event: an accepted, legal core-bus TXDATA write; ownership moves from CPU transaction to holding register. |
| `uart_rx_i` | Asynchronous physical input. It has no synchronous semantic meaning until it passes through the receiver's two-flop synchronizer. |
| `rx_byte_valid_o` | One-cycle event: a complete 8N1 frame with a valid stop bit produced `rx_byte_data_o`. |
| `rx_frame_error_o` | One-cycle event: the sampled stop bit was low. It is mutually exclusive with `rx_byte_valid_o`. |
| `rx_valid` | Level: FIFO count is nonzero, so a legal `RXDATA` read will return and pop the oldest byte. |
| `rx_full` | Level: FIFO count equals `RX_FIFO_DEPTH`. |
| `rx_overrun` | Sticky state: at least one good byte was dropped because the FIFO was full. |
| `rx_frame_error` | Sticky state: at least one invalid stop bit was observed. |
| `rx_push` | Event: a good receiver byte is accepted into available FIFO storage. |
| `rx_pop` | Event: an accepted legal `RXDATA` read observes a nonempty FIFO. |

The UART target receives only local offsets from the fabric. `TXDATA=0x00` is
an aligned, full-strobe word write whose low byte is enqueued. `STATUS=0x04` is
an aligned word read returning TX ready/busy in bits 0/1, RX valid/full in bits
2/3, sticky overrun/framing state in bits 4/5, and FIFO count in bits 15:8.
`RXDATA=0x08` is an aligned word read that returns and pops the oldest byte; an
empty read legally returns zero without a side effect. `RXERROR=0x0C` reads
overrun/framing in bits 0/1 and clears selected flags through a full-strobe
word write-one-to-clear. Other sizes, directions, strobes, or offsets return
one registered error and have no side effect.

A legal TXDATA request presented while the holding stage cannot accept remains
backpressured. Resource occupancy is not an error. The request payload must
remain stable until `req_valid && req_ready`; once accepted, exactly one
registered response follows.

Do not redefine ready as `!hold_full_q`: during simultaneous dequeue/enqueue,
the old byte transfers to the shifter and the newly accepted byte replaces it.
Ready describes transfer capability, not a single implementation bit.

The asynchronous RX pin is synchronized before the start/data/stop state
machine uses it. A good byte is enqueued only if storage is available. When
full, the newest byte is dropped, ordered queued data is preserved, and the
sticky overrun flag is set. A bad stop bit sets the sticky framing flag and
does not enqueue the byte. If software clears an error in the same cycle that
hardware reports a new occurrence, the hardware event wins.

## 12. GPIO signal semantics

| Signal/value | Semantic definition |
|---|---|
| `gpio_out_o` | Persistent external output level; equals the low `GPIO_WIDTH` bits of the GPIO output register. |
| `gpio_write` | Event: an accepted, legal write to `GPIO_OUT`; the only non-reset event allowed to change GPIO state. |
| `GPIO_OUT` local `0x00` | 32-bit software-visible R/W register. Reads return the containing word; writes merge only valid selected byte lanes. |
| `TARGET_GPIO` | Registered fabric response owner captured when a GPIO request is accepted. |

The fabric owns full-address decode and translates `0x1000_1000` to local
offset `0x00`. `core_bus_gpio` owns access legality, persistent state, partial
write merging, and its registered response. `riscv_soc` owns only composition
and the external port. Unsupported offsets, misaligned transfers,
size/strobe contradictions, or read strobes return an error without changing
state.

`GPIO_WIDTH` changes the physical output width, not the 32-bit software ABI.
Bits above `GPIO_WIDTH-1` read as zero and are not stored. This permits one
firmware register definition across boards with different LED counts.

## 13. Assertions required for new semantic contracts

- Invalid pipeline packets equal their canonical bubble.
- Invalid commands have all side-effect enables clear.
- A synchronous trap cannot coexist with RF write, CSR write, store effect, or
  `instret`.
- An asynchronous interrupt after normal retirement may coexist with RF/CSR
  effects and must save `next_pc`.
- Trap entry and MRET are mutually exclusive.
- Interrupt selection is suppressed while an instruction-owned multi-cycle
  operation has not reached retirement.
- WFI enters wait only after one retirement and cannot increment `minstret`
  again while waiting.
- The fabric accepts at most one target and routes a response only from the
  registered owner.
- Hardware MTIP in CSR reads/context equals the timer input regardless of CSR
  write data.
- UART byte ownership changes only on the corresponding valid/ready transfer.
- A full UART holding stage backpressures a legal TXDATA write without dropping
  it or returning an error.
- Invalid UART accesses produce no enqueue event.
- UART serial output is high when idle and emits exactly one start, eight data,
  and one stop bit for every shifter transfer.
- RX byte-valid and framing-error events are mutually exclusive.
- RX FIFO count never exceeds `RX_FIFO_DEPTH`; a full FIFO drops the newest
  arrival without changing the existing head or count.
- An empty RXDATA read completes with zero and never causes a FIFO underflow.
- A legal nonempty RXDATA read pops exactly once when the bus request is
  accepted.
- A same-cycle receive error takes priority over software W1C so the new event
  remains observable.
- GPIO state changes only after an accepted legal write.
- Invalid GPIO reads/writes produce one registered error and no pin change.
- A GPIO request uses a local address within its configured region.
- While `TARGET_GPIO` owns an outstanding transaction, no other response may
  be routed and the live request address must not select the return path.

## 14. Review checklist for future signals

Before adding a signal or struct, answer:

1. What exact fact does it represent?
2. Is it a candidate, intent, command, state, level, event, or observation?
3. Which module owns it?
4. In which cycle is it valid, and what invalidates it?
5. Is it instruction-associated, transaction-associated, or global state?
6. Must it advance/hold with existing fields?
7. Can it cause an architectural side effect?
8. Is a raw/effective distinction required?
9. Does it cross a registered boundary or clock domain?
10. Which assertion and directed test prove its contract?

If these questions cannot be answered, the signal is not ready to become a
stable interface.
