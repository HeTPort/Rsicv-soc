# AR-023 — Phase 5 Bare-Metal Runtime and FPGA-Equivalent Images

**Date:** 2026-08-14
**State:** Implemented and verified in ModelSim/Vivado; timer/GPIO and timer-IRQ verified on hardware, UART pending
**Stage:** Phase 5

## Problem

The Phase 4 assembly tests proved the CPU and individual peripherals, but they
did not establish the runtime assumptions needed by C or FreeRTOS. In
particular, the accepted map has program RAM at `0x0000_0000` and data RAM at
`0x8000_0000`, and the LSU cannot read program RAM. The old ELF converter
accepted only one contiguous region and mirrored every segment into both RAMs.
The SoC testbench declared `DATA_FILE` but did not load it, and the synthesis
boundary exposed neither firmware image.

Without fixing those boundaries, a C program could appear to work while using
the wrong stack, an uninitialized `gp`, zero-by-accident `.bss`, or simulation-
only hierarchical memory contents.

## Root cause

Earlier directed tests were linked entirely at address zero and were written
in assembly. That was adequate for ISA, trap, timer, UART, and GPIO work, but
it avoided the C ABI and split-memory runtime contract. A conventional `.data`
copy loop is not available because the data bus has no read path to instruction
BRAM.

## Options considered

1. Mirror all ELF segments into both RAMs. Rejected because it aliases regions
   that are architecturally distinct and cannot represent the 2 GiB gap.
2. Give `.data` a program-RAM load address and copy it at reset. Rejected
   because the LSU cannot read the copy source.
3. Add a boot ROM or data-visible program-memory window. Deferred because it
   expands the hardware beyond the first FreeRTOS target.
4. Preload independent local program/data BRAM images from the ELF. Selected
   because it matches the accepted hardware and works in simulation and
   bitstream initialization.

## Decision and implemented contract

- `_start` and the ELF entry are exactly `0x0000_0000`.
- `.text.startup`, `.text.trap`, and all executable code occupy program RAM.
- `.rodata`, `.data`, `.bss`, heap boundaries, and stacks occupy data RAM.
- `.data` and `.rodata` are preloaded directly into data BRAM; startup performs
  no impossible program-to-data copy.
- Startup masks interrupts, establishes 16-byte-aligned `sp`, initializes `gp`
  with relaxation disabled, clears `tp`, installs direct-mode `mtvec`, clears
  `.bss`, and calls `main`.
- Returning from `main` and unexpected traps report distinct failures through
  `tohost` and stop in local loops.
- The initial stack is 4 KiB below `0x8000_FFF0`; linker assertions prevent
  static data from overlapping it or `tohost`.
- The timer-interrupt demonstration replaces the weak fallback trap entry with
  a strong assembly entry that saves x1 and x3–x31 in a 128-byte aligned frame,
  calls C, restores the frame, and executes `mret`.

## Implementation surfaces

- `sim/regress/elf_to_mem.py` keeps its ACT4-compatible contiguous API and adds
  `convert_split` plus `--split-map` using generated map geometry.
- Split conversion rejects MMIO/unmapped/crossing segments, conflicting bytes,
  and an entry not equal to reset. Each local image is trimmed independently.
- `--dmem-uninitialized-fill 0xA5` poisons the ELF data segment's
  `p_memsz - p_filesz` tail. This makes `.bss` verification follow the ELF
  layout instead of a hard-coded testbench address.
- `riscv_soc` forwards Vivado-2019.2-compatible untyped program/data filename
  parameters to both RAMs. ModelSim uses the controlled testbench loader while
  reset remains asserted, avoiding time-zero ordering and string-type issues.
- `sw/common` owns the linker and reset runtime; `sw/drivers` owns minimal
  CSR/MMIO/UART/GPIO/timer/tohost access; `sw/apps` owns the three programs.
- `sw/build_firmware_wsl.sh` produces ELF, map, readelf, disassembly, size, and
  split image artifacts under `build/firmware/<app>/` and can install reviewed
  images under `testdata/`.

## Verification evidence

### Converter and generated map

```powershell
python -m unittest test_elf_to_mem.py test_import_act4.py
python tools/test_gen_soc_map.py
python tools/gen_soc_map.py --check
```

Results: 12/12 converter/importer tests, 9/9 map-generator tests, and generated
map freshness PASS.

### Phase 5 simulation

```powershell
./run_regression.ps1 -Manifest ./phase5_tests.json -Tag phase5
```

Results: 4/4 PASS:

- isolated separate data-image load;
- C startup and exact `Hello, UART!\r\n` serial waveform;
- timer-polled `01 -> 02 -> 04 -> 08 -> A5` GPIO waveform/readback;
- ten machine-timer interrupts with full-context return, ten observed trap
  entries, final GPIO `0x0A`, and `tohost=1`.

The hello data image contains `a5a5a5a5` at the ELF `.bss` tail. C observes
zero, proving startup performed the clear.

### Preservation

- directed smoke: 22/22 PASS;
- Phase 3 precise WFI and 10,000-interrupt tests: PASS;
- Phase 4 UART TX, RX echo, and GPIO: 3/3 PASS;
- focused retirement, CSR order, timer, UART TX/RX/targets, and GPIO target:
  eight tests PASS.

The separately modified `sim/tb/tb_soc_data_fabric.sv` had a pre-existing
failure at line 314 before Phase 5 work began. AR-023 did not modify that file.

### FPGA-equivalent BRAM initialization

```powershell
vivado -mode batch -source sim/synth/check_phase5_firmware_init.tcl
```

Vivado 2019.2 on provisional `xc7z010clg400-1` bound both installed hello image
paths, inferred 32 `RAMB36E1` primitives (16 program and 16 data), found
nonzero `INIT_xx` properties in both hierarchies, and wrote an OOC checkpoint.

This proves synthesis consumes the same images. It does not prove routed
timing, pin constraints, serial electrical behavior, or execution on a board.

## Problems found and lessons

1. ModelSim accepts `parameter string`, but Vivado 2019.2 rejects it during
   synthesis. Untyped string-literal parameters are required at the synthesis
   boundary; the controlled simulation loader avoids the transitive type clash.
2. A 100-tick interrupt interval was shorter than the full handler latency.
   MTIP was pending again at `mret`, causing immediate retraps; independent
   evidence showed 13 interrupts and GPIO `0x0D`. A 1000-tick interval leaves
   foreground-execution margin and passes with exactly ten interrupts.
3. A zero-initialized RAM cannot prove `.bss` startup. ELF-tail poisoning turns
   the runtime rule into an executable test without a brittle symbol address.

## Remaining gate

AR-024 supplies the exact board/revision, package, clock/reset/UART/LED pins,
XDC, board top, routed timing, and all three bitstreams. JTAG discovery was
recovered by installing the bundled Digilent runtime; `timer_gpio` and
`timer_irq` then passed on the physical board. The speed grade is still
unreadable, and physical completion still requires external-UART `hello` plus
repeated-reset evidence. See
[`AR024_ZYNQ_MINI_REVB_FPGA_INTEGRATION.md`](AR024_ZYNQ_MINI_REVB_FPGA_INTEGRATION.md).
