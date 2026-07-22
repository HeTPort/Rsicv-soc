OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

MEMORY
{
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00004000
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
  /* Reserve the final word, 0x3ffc, for the simulation tohost protocol. */
  ASSERT(_end <= 0x00003ffc, "ACT4 image overlaps tohost or exceeds 16 KiB DUT RAM")
}
