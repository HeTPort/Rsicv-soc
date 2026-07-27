OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

MEMORY
{
  /*
   * ACT4 programs are coverage-oriented and are substantially larger than the
   * synthesizable SoC's current 16 KiB RAM defaults.  The regression manifest
   * selects matching simulation-only RAM depths; this does not change the SoC
   * memory-map contract.
   */
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00040000
}

SECTIONS
{
  . = ORIGIN(ram);
  .text.init :
  {
    *(.text.init)
  } > ram

  .text.rvtest :
  {
    *(.text.rvtest)
    *(.text.rvtest.*)
  } > ram

  . = ALIGN(16);
  .data :
  {
    *(.data)
    *(.data.*)
    *(.rodata)
    *(.rodata.*)
    *(.sdata)
    *(.sdata.*)
  } > ram

  . = ALIGN(16);
  .text.rvmodel :
  {
    *(.text.rvmodel)
    *(.text.rvmodel.*)
    *(.text)
    *(.text.*)
  } > ram

  . = ALIGN(16);
  .bss (NOLOAD) :
  {
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(COMMON)
  } > ram

  _end = .;
  /* Reserve the final word, 0x3fffc, for the simulation tohost protocol. */
  ASSERT(_end <= 0x0003fffc, "ACT4 image overlaps tohost or exceeds 256 KiB simulation RAM")
}
