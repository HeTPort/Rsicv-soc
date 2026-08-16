OUTPUT_ARCH(riscv)
ENTRY(_start)

/* The generated fragment is the sole owner of RAM addresses and tohost. */
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
    *(.bss.startup_probe)
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
  __heap_end = __stack_bottom;
  PROVIDE(__freertos_irq_stack_top = __stack_top);

  PROVIDE(__global_pointer$ = ORIGIN(data_ram) + 0x800);

  /DISCARD/ :
  {
    *(.comment)
    *(.note .note.*)
  }
}

ASSERT(_start == ORIGIN(prog_ram),
       "reset entry is not at program-RAM origin")
ASSERT(__text_end <= ORIGIN(prog_ram) + LENGTH(prog_ram),
       "program RAM overflow")
ASSERT(__bss_end <= ORIGIN(data_ram) + LENGTH(data_ram),
       "data RAM overflow")
ASSERT(__static_end <= __stack_bottom,
       "static data overlaps reserved startup stack")
ASSERT(__stack_top + 0xC == SOC_TOHOST_ADDR,
       "unexpected stack/tohost layout")
ASSERT((__stack_top & 0xF) == 0,
       "initial stack is not 16-byte aligned")
ASSERT((__bss_start & 0x3) == 0 && (__bss_end & 0x3) == 0,
       "bss boundaries are not word aligned")
