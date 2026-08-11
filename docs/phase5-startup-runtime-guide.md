# Phase 5 Bare-Metal Startup and Runtime Guide

## 1. Purpose and status

This guide defines the first reusable software entry path for the custom
RV32IM SoC. It explains how to move from hardware reset at address
`0x0000_0000` to a C function safely and reproducibly:

```text
reset
  -> mask interrupts
  -> establish sp
  -> establish gp
  -> install a direct-mode mtvec target
  -> clear .bss
  -> call main(void)
  -> never fall through into arbitrary memory
```

This is an implementation guide, not a claim that the runtime already exists.
The proposed `startup.S`, full linker script, split-image conversion, and SoC
data-image load path remain Phase 5 work.

The immediate goal is a small freestanding C program that:

1. starts through the common reset entry;
2. proves initialized and zero-initialized data semantics;
3. prints `Hello, UART!\r\n` through the existing polling UART;
4. reports PASS through the reserved `tohost` word in simulation; and
5. uses the same ELF and memory images intended for later FPGA BRAM
   initialization.

FreeRTOS integration is deliberately later. A scheduler should not be used to
discover basic stack, linker, data-image, or trap-entry errors.

## 2. Repository contracts the runtime must obey

### 2.1 Reset and execution mode

The core resets its PC to `0x0000_0000` and executes in machine mode. The
linker's ELF entry is useful to tools, but hardware does not consult the ELF
header. Therefore all of the following must be true:

- `_start` is the ELF entry;
- `_start` is the first executable content at `0x0000_0000`;
- the instruction image places `_start` in program-RAM word zero; and
- the linker fails if `_start` moves away from the program-RAM origin.

Do not assume that `ENTRY(_start)` alone controls the hardware reset address.
It controls the ELF entry field, not the RTL reset vector.

### 2.2 Accepted split memory map

The accepted `freertos_split_64k_v1` layout is:

| Region | Address range | Runtime contents |
|---|---:|---|
| Program BRAM | `0x0000_0000..0x0000_FFFF` | reset entry, trap entry, `.text` |
| Timer MMIO | `0x0200_0000..0x0200_FFFF` | `mtimecmp`, `mtime` |
| UART MMIO | `0x1000_0000..0x1000_0FFF` | TX/RX/status/error registers |
| GPIO MMIO | `0x1000_1000..0x1000_1FFF` | output register |
| Data BRAM | `0x8000_0000..0x8000_FFFF` | `.rodata`, `.data`, `.bss`, heap, stacks |
| `tohost` | `0x8000_FFFC` | reserved simulation completion word |

The generated file `firmware/linker/soc_memory.ldh` owns the `MEMORY` regions
and `SOC_TOHOST_ADDR`. A handwritten linker script should include that file;
it must not copy these addresses into a second manually maintained table.

### 2.3 Why `.rodata` belongs in data BRAM

The core has separate instruction and data paths. The LSU can reach data RAM
and MMIO through the SoC fabric, but it cannot load constants from program
RAM. A C string placed beside `.text` in program RAM would therefore cause a
load access fault when C tries to read it.

Consequently:

- executable code belongs in program BRAM;
- constants read by software belong in data BRAM;
- writable initialized data belongs in data BRAM; and
- zero-initialized data, heap, and stacks belong in data BRAM.

This is a linker correctness rule, not merely a space-usage preference.

### 2.4 The `.data` initialization policy is preload, not copy

Many embedded systems store initial `.data` bytes in flash and copy them into
RAM at reset. That design requires the CPU to read the load image through its
data path. This SoC cannot read program BRAM through the LSU, so a classic
`__data_load_start -> __data_start` copy loop cannot work with the present
hardware.

For the first Phase 5 implementation:

- the ELF gives `.data` both its load and run address in data RAM;
- the image converter writes initialized bytes directly into a separate data
  BRAM image;
- simulation loads that image before releasing CPU reset;
- the FPGA flow uses the same data image as the data-BRAM initialization
  source; and
- `startup.S` does not copy `.data`.

If a future board flow cannot initialize data BRAM, the architecture will need
a boot loader, a data-visible ROM window, or another explicit copy source.
Startup assembly cannot invent a readable source that the bus does not expose.

### 2.5 `.bss` must still be cleared by startup

The C abstract-machine contract requires objects with static storage duration
and no explicit initializer to begin as zero. Data RAM currently defaults to
zero in simulation, and an ELF converter may also emit zero-filled `PT_LOAD`
tails. Neither is proof that startup fulfills the runtime contract.

The first runtime should clear `[__bss_start, __bss_end)` itself. Verification
should poison that range before reset release, then prove that C observes
zeros. This catches a missing or off-by-one loop that a friendly zero-filled
RAM would hide.

## 3. ABI principles behind `sp` and `gp`

### 3.1 Stack pointer (`sp`, x2)

The RV32 ILP32 ABI uses a downward-growing stack and requires `sp` to be
16-byte aligned at every standard procedure boundary. `_start` is not called
by another function, so it must create the first valid ABI boundary before it
executes `call main`.

The initial stack top should be a linker symbol, not a copied numeric address
in assembly. With the initial `medlow` policy, materialize the absolute symbol:

```asm
lui  sp, %hi(__stack_top)
addi sp, sp, %lo(__stack_top)
```

For the current map, `tohost` occupies the final word of data RAM. A safe
initial stack top is therefore the greatest 16-byte-aligned address below
`tohost`, currently `0x8000_FFF0`. The stack grows toward lower addresses.

The linker should define both the top and a reserved bottom:

```text
__stack_top    = align_down(SOC_TOHOST_ADDR, 16)
__stack_bottom = __stack_top - __stack_size
```

It must assert that all statically allocated data ends below
`__stack_bottom`. Without that assertion, a larger firmware image can silently
overlap the stack even though every individual section fits in data RAM.

The first bare-metal stack reservation can be 4 KiB. That is a bring-up value,
not the final FreeRTOS policy. Phase 6 will account separately for the startup
or interrupt stack, task stacks, queues, and heap.

### 3.2 Global pointer (`gp`, x3)

`gp` is a fixed ABI register. Linker relaxation may turn some two-instruction
symbol accesses into a single `gp`-relative load or store. If `gp` is wrong,
ordinary C code can access the wrong address even when the disassembly still
looks plausible.

The RISC-V psABI recommends initializing `gp` from the linker-defined
`__global_pointer$` symbol while locally disabling relaxation:

```asm
.option push
.option norelax
.Lset_gp:
    auipc gp, %pcrel_hi(__global_pointer$)
    addi  gp, gp, %pcrel_lo(.Lset_gp)
.option pop
```

The `.option norelax` region is essential. Without it, the linker can treat the
setup itself as a relaxation candidate and transform it into a sequence that
assumes `gp` was already valid.

For the first bring-up, compile consistently with `-msmall-data-limit=0` while
still initializing `gp`. This removes small-data placement as a second unknown
during basic startup verification. A later measured optimization may enable
small-data sections, place `.sdata`/`.sbss` within the `gp` reach window, and
add linker assertions for that window.

Do not use `gp` as a scratch register. The ABI treats both `gp` and `tp` as
unallocatable fixed registers.

## 4. Trap-vector principles

### 4.1 What writing `mtvec` does

`mtvec` holds a base address and a mode. This core implements direct mode only
and forces the base to four-byte alignment. In direct mode, synchronous
exceptions and machine interrupts enter at the same address. Software must
read `mcause` to distinguish them.

The startup sequence should install an aligned entry point:

```asm
la   t0, trap_entry
csrw mtvec, t0
```

The trap entry section must be executable, retained by the linker even when
`--gc-sections` is enabled, and aligned to at least four bytes.

### 4.2 Mask interrupts during initialization

Reset code should begin by disabling the global M-mode interrupt enable and
all currently used per-source enables:

```asm
csrci mstatus, 0x8       # clear mstatus.MIE
csrw  mie, zero          # clear machine interrupt enables
```

Install `mtvec` before any later code enables `mie.MTIE` or `mstatus.MIE`.
Enabling interrupts is a driver or application decision, not a generic startup
side effect.

### 4.3 Installing a vector is not a complete interrupt handler

An asynchronous trap may interrupt C at any instruction. A handler that calls
C or returns with `mret` must preserve every register that the interrupted
context could observe, as well as the necessary CSR state. The normal function
calling convention is insufficient because the interrupted code did not make
a call and therefore had no opportunity to save caller-clobbered registers.

The first startup milestone should use a non-returning assembly diagnostic
stub for unexpected traps. It may read `mcause`, `mepc`, and `mtval`, report a
failure, and loop. It should not call C and should not execute `mret`.

The later timer-interrupt milestone must add a separately reviewed context
frame and return path. FreeRTOS will ultimately own a still more complete
context-switch frame.

## 5. Proposed source layout

Keep generated ABI consumers separate from handwritten software:

```text
firmware/
  include/soc_memory_map.h       generated addresses and register locations
  linker/soc_memory.ldh          generated MEMORY regions and tohost symbol

sw/
  common/startup.S               reset entry, bss clear, initial trap stub
  common/linker.ld               complete section-placement policy
  common/runtime.h               optional runtime declarations
  drivers/uart.c
  drivers/uart.h
  apps/hello/main.c
  build_firmware_wsl.sh

build/firmware/hello/
  hello.elf
  hello.map
  hello.dis
  hello.size
  hello.imem.hex
  hello.dmem.hex
```

Generated build outputs belong under `build/` and should remain ignored.
Only reproducible sources, scripts, manifests, and selected test images should
be committed.

## 6. Linker script design

### 6.1 Responsibilities

The complete linker script must:

- declare `OUTPUT_ARCH(riscv)` and `ENTRY(_start)`;
- include `firmware/linker/soc_memory.ldh`;
- put startup first in program RAM;
- keep startup and trap entry from garbage collection;
- put all executable code in program RAM;
- put `.rodata`, `.data`, small data, and `.bss` in data RAM;
- export every symbol consumed by `startup.S`;
- reserve `tohost`, stack, and later heap boundaries;
- align the stack to 16 bytes and `.bss` to word boundaries;
- fail on program-RAM, data-RAM, stack, or `tohost` overlap; and
- avoid silently accepting important orphan sections.

Passing `-T sw/common/linker.ld` replaces GNU ld's default script. Therefore a
custom script must describe all allocatable sections the selected compiler
options can emit; it is not a small patch on top of a hidden default layout.

### 6.2 First implementation template

The following is a design template. Validate it with the installed RISC-V GNU
toolchain and inspect the resulting program headers before adopting it:

```ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

INCLUDE firmware/linker/soc_memory.ldh

PROVIDE(__stack_size = 0x1000);

SECTIONS
{
  . = ORIGIN(prog_ram);

  .text ALIGN(4) :
  {
    __text_start = .;
    KEEP(*(.text.startup))
    KEEP(*(.text.trap))
    *(.text .text.*)
    . = ALIGN(4);
    __text_end = .;
  } > prog_ram

  . = ORIGIN(data_ram);

  .rodata ALIGN(4) :
  {
    __rodata_start = .;
    *(.rodata .rodata.*)
    . = ALIGN(4);
    __rodata_end = .;
  } > data_ram

  .data ALIGN(4) :
  {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
    __data_end = .;
  } > data_ram

  .bss ALIGN(4) (NOLOAD) :
  {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > data_ram

  __static_end = ALIGN(16);
  __heap_start = __static_end;

  __stack_top = SOC_TOHOST_ADDR & ~0xF;
  __stack_bottom = __stack_top - __stack_size;

  PROVIDE(__global_pointer$ = ORIGIN(data_ram) + 0x800);
}

ASSERT(_start == ORIGIN(prog_ram),
       "reset entry is not at program-RAM origin")
ASSERT(__text_end <= ORIGIN(prog_ram) + LENGTH(prog_ram),
       "program RAM overflow")
ASSERT(__static_end <= __stack_bottom,
       "static data/heap boundary overlaps reserved startup stack")
ASSERT(__stack_top + 0xC == SOC_TOHOST_ADDR,
       "unexpected stack/tohost layout")
ASSERT((__stack_top & 0xF) == 0,
       "initial stack is not 16-byte aligned")
```

The `__global_pointer$` definition above accompanies the initial
`-msmall-data-limit=0` policy. Do not enable small-data relaxation later
without replacing it with an intentional `.sdata`/`.sbss` layout and range
assertions.

The template intentionally has no `.data` `AT > prog_ram` clause and no
`__data_load_start`: `.data` is preinitialized directly in data BRAM.

### 6.3 Sections that require an explicit policy

During the first link, use a map file and an orphan-section warning. Review any
of these if they appear:

- `.init_array`, `.fini_array`: C/C++ constructors require startup walkers;
- `.eh_frame`, `.gcc_except_table`: unwind/exception metadata is not part of
  the initial C subset;
- `.got`, `.got.plt`, `.plt`, dynamic sections: unexpected for a non-PIC,
  statically linked freestanding image;
- `.tdata`, `.tbss`: thread-local storage needs a `tp` and TLS initialization
  contract;
- `.sdata`, `.sbss`: must match the selected small-data and `gp` policy; and
- unexpected allocatable orphan sections: must never be accepted on guesswork.

Use compiler flags to suppress unused runtime features, but keep the linker
review as the final authority. A flag is not proof that no input object emitted
the section.

## 7. Proposed `startup.S`

### 7.1 Annotated template

```asm
    .section .text.startup, "ax", @progbits
    .align  2
    .globl  _start
    .type   _start, @function

_start:
    /* No asynchronous interrupt may enter before the runtime is ready. */
    csrci   mstatus, 0x8
    csrw    mie, zero

    /* Establish the first valid ILP32 procedure stack. */
    lui     sp, %hi(__stack_top)
    addi    sp, sp, %lo(__stack_top)

    /* Set gp exactly as required by the RISC-V psABI. */
    .option push
    .option norelax
.Lset_gp:
    auipc   gp, %pcrel_hi(__global_pointer$)
    addi    gp, gp, %pcrel_lo(.Lset_gp)
    .option pop

    /* This first milestone has one hart and no TLS runtime. */
    mv      tp, zero

    /* Direct-mode trap entry; the symbol is four-byte aligned. */
    la      t0, trap_entry
    csrw    mtvec, t0

    /* Linker guarantees word-aligned start/end boundaries. */
    lui     t0, %hi(__bss_start)
    addi    t0, t0, %lo(__bss_start)
    lui     t1, %hi(__bss_end)
    addi    t1, t1, %lo(__bss_end)
    bgeu    t0, t1, .Lbss_done

.Lbss_clear:
    sw      zero, 0(t0)
    addi    t0, t0, 4
    bltu    t0, t1, .Lbss_clear

.Lbss_done:
    /* Freestanding application contract: int main(void). */
    call    main

    /* Returning from main is an explicit failure, never fall-through. */
    lui     t0, %hi(__soc_tohost)
    addi    t0, t0, %lo(__soc_tohost)
    li      t1, 0xBAD00002
    sw      t1, 0(t0)

.Lmain_returned:
    j       .Lmain_returned

    .size   _start, . - _start

    .section .text.trap, "ax", @progbits
    .align  2
    .globl  trap_entry
    .type   trap_entry, @function

trap_entry:
    /* Diagnostic-only: do not call C and do not attempt mret here. */
    csrci   mstatus, 0x8
    csrw    mie, zero
    csrr    t0, mcause
    csrr    t1, mepc
    csrr    t2, mtval

    lui     t0, %hi(__soc_tohost)
    addi    t0, t0, %lo(__soc_tohost)
    li      t1, 0xBAD00001
    sw      t1, 0(t0)

.Lunexpected_trap:
    j       .Lunexpected_trap

    .size   trap_entry, . - trap_entry
```

### 7.2 Why the order matters

1. Interrupts are masked before touching runtime-owned state.
2. `sp` is valid before the first function call or stack spill.
3. `gp` is valid before relaxed global accesses can occur.
4. `tp` gets a deterministic single-hart value before future TLS or scheduler
   work assigns it a stronger meaning.
5. `mtvec` is installed before any code deliberately enables interrupts.
6. `.bss` is cleared before C observes zero-initialized objects.
7. `main` is called only after the ABI and C storage contracts hold.
8. A returned `main` reports an error and loops instead of fetching unrelated
   words after the startup section.

The startup code does not initialize general-purpose registers that the ABI
defines as caller-clobbered or callee-saved. C code cannot assume arbitrary
registers are zero. Only architectural or runtime-required state should be
initialized.

## 8. Compiler and linker policy

Use the compiler driver for both compilation and final linking so it selects
the correct RISC-V multilib and can add `libgcc` helpers if the code needs
them. A suitable first policy is:

```text
-march=rv32im_zicsr
-mabi=ilp32
-mcmodel=medlow
-msmall-data-limit=0
-ffreestanding
-fno-builtin
-fno-pic
-fno-pie
-fno-stack-protector
-fno-unwind-tables
-fno-asynchronous-unwind-tables
-ffunction-sections
-fdata-sections
-Wall -Wextra -Werror
```

Link with at least:

```text
-nostartfiles
-nostdlib
-no-pie
-Wl,--gc-sections
-Wl,--no-relax
-Wl,--orphan-handling=warn
-Wl,-Map,build/firmware/hello/hello.map
-T sw/common/linker.ld
```

Add `-lgcc` at the end if generated code requires compiler helper routines.
Do not add a hosted C library until `_sbrk`, file I/O, exit behavior, errno,
and reentrancy policies have been designed. The first UART program needs no
libc and should not use `printf`.

Using `--no-relax` globally at first makes disassembly easier to audit. The
local `.option norelax` around `gp` remains required so startup stays correct
when global relaxation is enabled later.

## 9. Split-image generation: required Phase 5 prerequisite

### 9.1 Current limitation

`sim/regress/elf_to_mem.py` currently accepts one contiguous RAM base/size and
mirrors each `PT_LOAD` segment into both memories. It rejects an ELF containing
segments at both `0x0000_0000` and `0x8000_0000`. That behavior was sufficient
for earlier tests but is not sufficient for the accepted Phase 5 linker map.

The converter must be extended before the C runtime can be called complete.

### 9.2 Required converter behavior

For every ELF `PT_LOAD` segment:

1. use its physical address, falling back to virtual address only under the
   converter's existing rule;
2. if the whole segment is in program RAM, copy it only to the instruction
   image at `address - SOC_PROG_RAM_BASE`;
3. if the whole segment is in data RAM, copy initialized bytes only to the
   data image at `address - SOC_DATA_RAM_BASE`;
4. reject segments in MMIO or unmapped space;
5. reject a segment crossing a region boundary;
6. reject conflicting overlapping bytes;
7. require the ELF entry to equal the program-RAM reset entry; and
8. emit deterministic word-oriented little-endian `$readmemh` files.

The converter should consume generated map values or explicit checked
arguments. It must not introduce another hard-coded copy of the memory map.

Add unit tests for:

- one program segment plus one data segment;
- initialized `.data` bytes in the data image only;
- `.bss` `p_memsz > p_filesz` behavior;
- exact start/end boundaries;
- segment-crossing rejection;
- MMIO/unmapped rejection;
- overlap conflict rejection; and
- reset entry outside program RAM.

## 10. SoC data-image loading: required Phase 5 prerequisite

The regression runner already recognizes a manifest `data_image` and forwards
it as the `DATA_FILE` generic. However, `tb_riscv_soc.sv` currently declares
`DATA_FILE` without loading it, and `riscv_soc.sv` does not pass a data-RAM
initialization file into `core_bus_data_ram`.

Choose and verify one coherent mechanism:

### Simulation

While CPU reset is held, load both images explicitly:

```systemverilog
$readmemh(PROGRAM_FILE, u_dut.u_prog_ram.mem);
if (DATA_FILE != "")
  $readmemh(DATA_FILE, u_dut.u_data_target.u_data_ram.mem);
```

Release `load_done` only after both loads complete. This matches the existing
testbench's controlled program-loading phase and avoids time-zero ordering
races.

### Synthesis and FPGA initialization

Add explicit program/data initialization parameters through `riscv_soc` and
forward the data parameter through `core_bus_data_ram` to `data_ram.INIT_FILE`.
The final Vivado flow must prove that both selected images become BRAM INIT
contents. A simulation-only hierarchical load does not prove bitstream
initialization.

Keep the dynamic simulation loader and synthesizable parameter path consistent
about file format and local word addressing.

## 11. First C validation program

The first `main.c` should be a diagnostic, not a demo that can pass while
startup is partly broken. Include:

```c
static volatile uint32_t bss_probe;
static volatile uint32_t data_probe = 0x12345678u;
static const char message[] = "Hello, UART!\r\n";
```

Before printing, verify:

- `bss_probe == 0` after the testbench poisoned its backing word before reset;
- `data_probe == 0x12345678` from the separate data image;
- the first and last bytes of `message` are correct, proving `.rodata` is on
  the data path;
- the live `sp` value is 16-byte aligned and within the reserved stack range;
- the live `gp` equals `__global_pointer$`; and
- `mtvec` equals the aligned `trap_entry` address.

Use distinct nonzero `tohost` failure codes for each check. Print only after
the runtime invariants pass. Wait for UART `TX_BUSY` to clear before writing
PASS so the simulator does not terminate before the final stop bit.

## 12. Verification ladder

### Gate A: static ELF and linker inspection

Archive and inspect:

```powershell
riscv64-unknown-elf-readelf -h -l -S -s hello.elf
riscv64-unknown-elf-objdump -drwC hello.elf
riscv64-unknown-elf-size -A hello.elf
```

Confirm:

- ELF class is 32-bit little-endian RISC-V;
- entry is `0x0000_0000`;
- executable load segments are entirely in program RAM;
- readable/writable data segments are entirely in data RAM;
- no load segment covers MMIO or `tohost`;
- `_start`, `trap_entry`, `__bss_start/end`, `__stack_bottom/top`,
  `__global_pointer$`, and `main` have expected addresses;
- `_start` disassembly contains the relaxation-safe `gp` sequence;
- `sp` is established before `call main`; and
- no unsupported ISA instructions were emitted.

### Gate B: converter unit tests

Run the existing converter tests plus new split-region cases. Verify image
word zero contains `_start`, initialized globals appear only at their data-RAM
offsets, and no enormous sparse file is emitted for the architectural gap.

### Gate C: focused startup simulation

Before reset release:

1. load instruction and data images;
2. overwrite the ELF `.bss` range with a nonzero poison pattern;
3. optionally place canaries immediately below and above that range; and
4. release the CPU only after all writes are complete.

Check that startup clears exactly `.bss`, preserves the canaries and `.data`,
sets `sp`/`gp`/`mtvec`, reaches `main` once, and reports the expected result.

### Gate D: SoC UART regression

Decode the actual `uart_tx_o` waveform and require the exact message plus a
committed `tohost == 1` store after the last UART stop bit. Do not treat an
internal UART register write as proof of pin-level transmission.

### Gate E: preservation regression

After adding the runtime path, rerun:

- focused data-fabric/GPIO/UART/timer tests;
- Phase 3 timer/WFI tests;
- Phase 4 UART/GPIO tests;
- the 22-test smoke suite;
- converter/map unit tests; and
- the relevant Vivado OOC synthesis boundary.

### Gate F: FPGA equivalence

Later, use the same ELF-derived instruction and data contents in Vivado. The
board test should observe the UART message and a GPIO heartbeat. Physical
completion additionally requires the exact board part, clock/reset design,
UART/LED pins, I/O standard, timing constraints, and programmed-hardware
evidence.

## 13. Common mistakes and their symptoms

| Mistake | Likely symptom | Corrective check |
|---|---|---|
| `_start` is not at address zero | immediate invalid fetch or unrelated instruction | linker `ASSERT` plus ELF entry/disassembly check |
| `sp` points at `0x8001_0000` | first push faults because that address is outside RAM | use aligned symbol below `tohost` |
| `sp` is only four-byte aligned | simple code may work; ABI-compliant calls or interrupt frames later fail | assert and read live `sp & 0xF` |
| `gp` setup is relaxed | small global accesses read/write wrong locations | use the psABI `.option norelax` sequence |
| `.rodata` is placed with `.text` | UART string load causes data access fault | place constants in data RAM |
| `.data` uses `AT > prog_ram` | reset copy loop faults; LSU cannot read program RAM | preload a separate data image |
| `.bss` appears zero without a loop | test passes only because RAM defaulted to zero | poison `.bss` before reset release |
| `mtvec` is installed after interrupts are enabled | early timer event redirects to reset/zero | mask interrupts, install vector first |
| trap stub calls C without a frame | interrupted registers are corrupted | keep initial stub non-returning; design context save separately |
| `main` returns into adjacent bytes | random execution or late trap | report failure and loop after `call main` |
| linker accepts orphan sections | code/data lands in unintended RAM | warn/error on orphans and inspect the map |
| only the instruction image is loaded | initialized globals contain zero/X | connect and verify `DATA_FILE` path |
| simulation uses hierarchical data load only | simulation passes but FPGA globals are wrong | prove data-BRAM INIT in synthesis/bitstream flow |

## 14. Recommended implementation sequence

Keep each step independently reviewable:

1. **Roadmap and executable contracts**
   - accept this guide;
   - correct stale Phase 4 status;
   - add RED linker/converter/startup tests.
2. **Full linker script**
   - add section placement and symbols;
   - link a minimal `_start` object;
   - inspect ELF headers, map, symbols, and disassembly.
3. **Split-image converter**
   - extend the existing converter;
   - add boundary and rejection unit tests.
4. **SoC data-image plumbing**
   - make `DATA_FILE` effective in `tb_riscv_soc`;
   - add synthesizable data initialization parameters;
   - prove program/data images are loaded before reset release.
5. **Startup assembly**
   - establish `sp`/`gp`/`tp`/`mtvec`;
   - clear `.bss`;
   - call `main` and handle unexpected return/trap.
6. **C UART hello**
   - add minimal polling driver and diagnostic globals;
   - verify exact serial waveform and `tohost` result.
7. **Phase 5 timer programs**
   - timer-polled GPIO toggle;
   - timer-interrupt counter with a reviewed context frame and `mret`.
8. **FPGA sanity gate**
   - run the same three programs with the same ELF-derived memory contents on
     the exact board before starting FreeRTOS.

## 15. Completion checklist

- [ ] `_start` is linked and loaded at `0x0000_0000`.
- [ ] `sp` is linker-defined, inside data RAM, below `tohost`, and 16-byte aligned.
- [ ] `gp` is initialized with the relaxation-safe psABI sequence.
- [ ] `mtvec` points to an aligned direct-mode assembly entry before interrupts.
- [ ] `.rodata` and `.data` are directly preloaded into data BRAM.
- [ ] `.bss` is actively cleared and verified from a poisoned initial state.
- [ ] Returning from `main` and unexpected traps report failure and loop.
- [ ] Split ELF conversion has positive, boundary, and rejection tests.
- [ ] `tb_riscv_soc.DATA_FILE` changes actual data-RAM contents.
- [ ] Vivado uses the intended instruction and data BRAM initial contents.
- [ ] ELF/map/disassembly/size artifacts are reproducible.
- [ ] UART hello passes at the physical serial pin model and through `tohost`.
- [ ] Existing focused, phase, smoke, map, and synthesis gates remain green.

## 16. References

Repository contracts:

- [Project roadmap](../TODO.md)
- [Architectural memory-map decision](../doc/AR009_ARCHITECTURAL_MEMORY_MAP.md)
- [Machine-readable map decision](../doc/AR014_MACHINE_READABLE_SOC_MAP.md)
- [Core-to-SoC environment contract](../doc/AR016_CORE_TO_SOC_ENVIRONMENT_CONTRACT.md)
- [Precise timer-interrupt implementation](../doc/AR008_PRECISE_MACHINE_TIMER_INTERRUPTS.md)
- [Generated linker memory fragment](../firmware/linker/soc_memory.ldh)
- [Generated C memory-map header](../firmware/include/soc_memory_map.h)
- [Current ELF converter](../sim/regress/elf_to_mem.py)
- [Current SoC testbench](../sim/tb/tb_riscv_soc.sv)

External primary specifications:

- [RISC-V ABIs Specification](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/)
- [RISC-V Machine-Level ISA](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [GNU ld linker scripts](https://sourceware.org/binutils/docs/ld/Scripts.html)
- [GNU ld assertions and miscellaneous commands](https://sourceware.org/binutils/docs/ld/Miscellaneous-Commands.html)
