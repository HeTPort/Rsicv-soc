# AR-022 — Memory-Mapped GPIO Output

**Date:** 2026-08-11

**State:** Verified

**Stage:** Phase 4 minimal peripherals

## Problem

The accepted SoC map reserved a 4 KiB GPIO window at `0x1000_1000`, but a
region reservation alone does not implement register behavior. The SoC needed
a small output register that firmware could write and read back, an observable
pin-level output for simulation and later FPGA LEDs, and a fifth registered
response owner in the single-outstanding data fabric.

## Root cause and initial RED evidence

Before this change, GPIO addresses either reached the default error target or
could not elaborate against the proposed fabric test because the fabric had no
GPIO parameters or ports. The map described *where* GPIO belongs; no module
owned the state or side effects.

The first registered-owner test also produced
`data fabric request changed under back-pressure`. The testbench kept
`cpu_req_valid=1` while the accepted GPIO transaction was outstanding, then
changed the request address from GPIO to UART. With `ready=0`, valid/ready
rules require the entire request payload to remain stable. This was a stimulus
bug, not a decoder failure. The corrected test changes only observational
address bits while `valid=0`; the returning response still must follow the
registered GPIO owner.

## Options considered

1. Put the GPIO register directly in `riscv_soc.sv`. This is short, but mixes
   address legality, bus timing, state, and composition at the top level.
2. Bridge an external peripheral bus. This adds protocol conversion without a
   present need; the CPU already has a suitable native bus.
3. Add a native `core_bus_gpio` target. This preserves the same ownership
   boundary used by timer, UART, RAM, and the default target.

Option 3 was selected.

## Decision and contract

- `config/soc_map.json` is the canonical address source.
- The GPIO region is `0x1000_1000..0x1000_1fff`.
- `GPIO_OUT` is a 32-bit software-visible R/W register at local offset `0x00`.
- `GPIO_WIDTH` selects how many low register bits reach `gpio_out_o`; the
  default is eight. `RESET_VALUE` defines reset pin state.
- Legal byte, aligned halfword, and aligned word accesses use exactly matching
  strobes. Writes merge selected byte lanes. Reads return the containing
  32-bit register word; the LSU performs byte/halfword selection and extension.
- Unsupported offsets, misaligned sizes, contradictory strobes, and read
  strobes return one registered error response and have no side effect.
- GPIO state changes only on `req_valid && req_ready && legal && write`.
- The fabric decodes the full address, subtracts `SOC_GPIO_BASE`, and records
  `TARGET_GPIO` at request acceptance. Because the fabric now has timer, UART,
  GPIO, RAM, and default owners, its enum is three bits.

## Signal flow

```text
CPU store/load
    |
    v
LSU core_bus_req_t (full address 0x1000_1000)
    |
    v
soc_data_fabric
  - decode GPIO window
  - translate address to local 0x00
  - register TARGET_GPIO on acceptance
    |
    v
core_bus_gpio
  - validate address/size/strobes
  - merge accepted write lanes into GPIO_OUT
  - return one registered core_bus_rsp_t
    |
    +--------------------> gpio_out_o[GPIO_WIDTH-1:0]
    |
    v
fabric response mux selected by registered TARGET_GPIO
    |
    v
LSU completion -> retirement
```

The response mux deliberately does not use the live request address. Request
and response can be separated by cycles, so the accepted target—not whatever
address happens to be visible later—owns the response.

## Consequences

- GPIO behavior is independently reusable and testable.
- `riscv_soc.sv` remains composition logic rather than a peripheral register
  implementation.
- Software sees a stable 32-bit ABI while a board may expose a smaller number
  of pins.
- Partial writes are useful and deterministic, but they require the target to
  validate both transfer size and strobes.
- Input GPIO, direction control, set/clear registers, and interrupts remain
  separate future work. The first output-only board mapping and LED electrical
  behavior are physically verified on ZYNQ MINI REVB under AR024.

## Verification evidence

- `python tools/gen_soc_map.py --check`: PASS.
- `python -m unittest tools.test_gen_soc_map`: 9/9 PASS.
- `sim/run_core_bus_gpio.do`: PASS at 210 ns, zero errors. Covers reset,
  readback, width masking, byte merge, malformed accesses, no invalid side
  effects, and registered response timing.
- `sim/run_soc_data_fabric.do`: PASS at 176 ns, zero errors. Covers full address
  `0x1000_1000`, local offset `0x00`, mutual exclusion, and registered
  `TARGET_GPIO` response ownership.
- `soc_gpio_out_test`: PASS. Firmware writes and reads back
  `01, 02, 04, 08, A5`; the SoC testbench observes the same pin transitions.
- Phase 4: 3/3 PASS. Phase 3: 2/2 PASS. Smoke: 22/22 PASS.
- Vivado 2019.2 OOC: 0 errors, 0 critical warnings, 32 BRAMs, two retained LSU
  state cells, 389 UART-hierarchy objects, and 20 GPIO-hierarchy objects.

## Long-term principles

1. An address map is a contract, not an implementation.
2. Decode belongs to the fabric; register legality and side effects belong to
   the target; pin exposure belongs to the SoC boundary.
3. Side effects occur on accepted legal transactions, never merely because
   address and write data are present.
4. Under back-pressure, `valid` keeps the payload stable. To inspect unrelated
   live address bits without presenting a request, deassert `valid`.
5. Delayed responses are routed by registered ownership, not re-decoding.
