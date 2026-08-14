#!/usr/bin/env python3
"""Convert a little-endian RV32 ELF into Harvard instruction/data RAM images.

Only the Python standard library is used so the converter works in both the
Windows Python bundled with this workspace and a normal WSL Python install.
Every PT_LOAD segment is copied into both memories. This gives the Harvard
simulation model the same initial byte contents as the unified address space
described by the ELF while still allowing instruction and data RAM to diverge
after reset.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path


ELF_MAGIC = b"\x7fELF"
ELFCLASS32 = 1
ELFDATA2LSB = 1
EM_RISCV = 243
PT_LOAD = 1


def integer(text: str) -> int:
    """Parse decimal or a 0x/0o/0b-prefixed integer from the command line."""
    return int(text, 0)


@dataclass(frozen=True)
class LoadSegment:
    address: int
    file_data: bytes
    memory_size: int
    flags: int


@dataclass(frozen=True)
class ElfImage:
    entry: int
    segments: tuple[LoadSegment, ...]


def read_elf(path: Path) -> ElfImage:
    raw = path.read_bytes()
    if len(raw) < 52:
        raise ValueError(f"{path}: file is too small to be an ELF32 image")

    header = struct.unpack_from("<16sHHIIIIIHHHHHH", raw, 0)
    ident = header[0]
    machine = header[2]
    version = header[3]
    entry = header[4]
    phoff = header[5]
    ehsize = header[8]
    phentsize = header[9]
    phnum = header[10]

    if ident[:4] != ELF_MAGIC:
        raise ValueError(f"{path}: missing ELF magic")
    if ident[4] != ELFCLASS32:
        raise ValueError(f"{path}: only ELF32 is supported")
    if ident[5] != ELFDATA2LSB:
        raise ValueError(f"{path}: only little-endian ELF is supported")
    if machine != EM_RISCV:
        raise ValueError(f"{path}: ELF machine {machine} is not RISC-V ({EM_RISCV})")
    if version != 1 or ident[6] != 1:
        raise ValueError(f"{path}: unsupported ELF version")
    if ehsize < 52 or phentsize < 32:
        raise ValueError(f"{path}: malformed ELF/program header size")
    if phoff + phnum * phentsize > len(raw):
        raise ValueError(f"{path}: program-header table extends past end of file")

    segments: list[LoadSegment] = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        fields = struct.unpack_from("<IIIIIIII", raw, offset)
        p_type, p_offset, p_vaddr, p_paddr = fields[:4]
        p_filesz, p_memsz, p_flags = fields[4:7]
        if p_type != PT_LOAD or p_memsz == 0:
            continue
        if p_filesz > p_memsz:
            raise ValueError(f"{path}: PT_LOAD {index} has filesz larger than memsz")
        if p_offset + p_filesz > len(raw):
            raise ValueError(f"{path}: PT_LOAD {index} extends past end of file")

        # Linkers normally make p_paddr and p_vaddr equal for this bare-metal
        # target. Prefer the physical address, falling back to virtual when the
        # physical field is left as zero for a nonzero virtual address.
        address = p_paddr if p_paddr != 0 or p_vaddr == 0 else p_vaddr
        segments.append(
            LoadSegment(address, raw[p_offset : p_offset + p_filesz], p_memsz, p_flags)
        )

    if not segments:
        raise ValueError(f"{path}: ELF contains no loadable segments")
    return ElfImage(entry, tuple(segments))


def fill_words(size: int, word: int) -> bytearray:
    if size <= 0 or size % 4 != 0:
        raise ValueError("memory size must be a positive multiple of four bytes")
    pattern = (word & 0xFFFF_FFFF).to_bytes(4, "little")
    return bytearray(pattern * (size // 4))


def build_memories(
    elf: ElfImage, base: int, size: int, instruction_fill: int
) -> tuple[bytearray, bytearray]:
    imem = fill_words(size, instruction_fill)
    dmem = bytearray(size)
    loaded: dict[int, int] = {}

    for segment in elf.segments:
        start = segment.address
        end = start + segment.memory_size
        if start < base or end > base + size:
            raise ValueError(
                f"PT_LOAD [0x{start:08x}, 0x{end:08x}) is outside configured "
                f"RAM [0x{base:08x}, 0x{base + size:08x})"
            )

        contents = segment.file_data + bytes(segment.memory_size - len(segment.file_data))
        destination = start - base
        for byte_index, value in enumerate(contents):
            absolute = start + byte_index
            previous = loaded.get(absolute)
            if previous is not None and previous != value:
                raise ValueError(
                    f"conflicting PT_LOAD bytes at address 0x{absolute:08x}: "
                    f"0x{previous:02x} versus 0x{value:02x}"
                )
            loaded[absolute] = value
        imem[destination : destination + len(contents)] = contents
        dmem[destination : destination + len(contents)] = contents

    if not (base <= elf.entry < base + size):
        raise ValueError(
            f"ELF entry 0x{elf.entry:08x} is outside configured RAM "
            f"[0x{base:08x}, 0x{base + size:08x})"
        )
    return imem, dmem


def _validate_region(name: str, base: int, size: int) -> None:
    if base < 0:
        raise ValueError(f"{name} base must be nonnegative")
    if size <= 0 or size % 4 != 0:
        raise ValueError(f"{name} size must be a positive multiple of four bytes")


def _segment_contents(segment: LoadSegment, uninitialized_fill: int = 0) -> bytes:
    if not 0 <= uninitialized_fill <= 0xFF:
        raise ValueError("uninitialized byte fill must be in the range 0..255")
    tail_size = segment.memory_size - len(segment.file_data)
    return segment.file_data + bytes([uninitialized_fill]) * tail_size


def _install_segment(
    memory: bytearray,
    loaded: dict[int, int],
    segment: LoadSegment,
    region_base: int,
    uninitialized_fill: int = 0,
) -> None:
    contents = _segment_contents(segment, uninitialized_fill)
    for byte_index, value in enumerate(contents):
        absolute = segment.address + byte_index
        previous = loaded.get(absolute)
        if previous is not None and previous != value:
            raise ValueError(
                f"conflicting PT_LOAD bytes at address 0x{absolute:08x}: "
                f"0x{previous:02x} versus 0x{value:02x}"
            )
        loaded[absolute] = value
    destination = segment.address - region_base
    memory[destination : destination + len(contents)] = contents


def build_split_memories(
    elf: ElfImage,
    program_base: int,
    program_size: int,
    data_base: int,
    data_size: int,
    instruction_fill: int,
    data_uninitialized_fill: int = 0,
) -> tuple[bytearray, bytearray]:
    """Build independent local images for the accepted split-RAM SoC model."""

    _validate_region("program RAM", program_base, program_size)
    _validate_region("data RAM", data_base, data_size)
    program_end = program_base + program_size
    data_end = data_base + data_size
    if program_base < data_end and data_base < program_end:
        raise ValueError("program RAM and data RAM regions overlap")
    if elf.entry != program_base:
        raise ValueError(
            f"ELF entry 0x{elf.entry:08x} does not equal reset entry "
            f"0x{program_base:08x}"
        )

    imem = fill_words(program_size, instruction_fill)
    dmem = bytearray(data_size)
    program_loaded: dict[int, int] = {}
    data_loaded: dict[int, int] = {}

    for segment in elf.segments:
        start = segment.address
        end = start + segment.memory_size
        in_program = program_base <= start and end <= program_end
        in_data = data_base <= start and end <= data_end
        if in_program:
            _install_segment(imem, program_loaded, segment, program_base)
        elif in_data:
            _install_segment(
                dmem,
                data_loaded,
                segment,
                data_base,
                data_uninitialized_fill,
            )
        else:
            raise ValueError(
                f"PT_LOAD [0x{start:08x}, 0x{end:08x}) is not wholly inside "
                f"program RAM [0x{program_base:08x}, 0x{program_end:08x}) or "
                f"data RAM [0x{data_base:08x}, 0x{data_end:08x})"
            )

    return imem, dmem


def write_readmemh(path: Path, memory: bytearray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as output:
        for offset in range(0, len(memory), 4):
            word = int.from_bytes(memory[offset : offset + 4], "little")
            output.write(f"{word:08x}\n")


def convert(
    elf_path: Path,
    imem_path: Path,
    dmem_path: Path,
    base: int = 0,
    size: int = 0x4000,
    instruction_fill: int = 0x0010_0073,
) -> ElfImage:
    elf = read_elf(elf_path)
    imem, dmem = build_memories(elf, base, size, instruction_fill)
    # $readmemh leaves the rest of each already-initialized RAM unchanged.
    # Emit only through the highest loaded byte instead of padding every ACT4
    # image to the simulation RAM capacity.
    used_size = max(segment.address + segment.memory_size for segment in elf.segments) - base
    used_size = (used_size + 3) & ~3
    write_readmemh(imem_path, imem[:used_size])
    write_readmemh(dmem_path, dmem[:used_size])
    return elf


def _local_used_size(
    segments: tuple[LoadSegment, ...], region_base: int, region_size: int
) -> int:
    region_end = region_base + region_size
    local_ends = [
        segment.address + segment.memory_size - region_base
        for segment in segments
        if region_base <= segment.address
        and segment.address + segment.memory_size <= region_end
    ]
    if not local_ends:
        return 0
    return (max(local_ends) + 3) & ~3


def convert_split(
    elf_path: Path,
    imem_path: Path,
    dmem_path: Path,
    program_base: int,
    program_size: int,
    data_base: int,
    data_size: int,
    instruction_fill: int = 0x0010_0073,
    data_uninitialized_fill: int = 0,
) -> ElfImage:
    elf = read_elf(elf_path)
    imem, dmem = build_split_memories(
        elf,
        program_base,
        program_size,
        data_base,
        data_size,
        instruction_fill,
        data_uninitialized_fill,
    )
    program_used = _local_used_size(elf.segments, program_base, program_size)
    data_used = _local_used_size(elf.segments, data_base, data_size)
    write_readmemh(imem_path, imem[:program_used])
    write_readmemh(dmem_path, dmem[:data_used])
    return elf


def split_regions_from_map(path: Path) -> tuple[int, int, int, int]:
    """Read program/data RAM geometry from a generated simulation map."""

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read split memory map {path}: {error}") from error
    regions = raw.get("regions")
    if not isinstance(regions, list):
        raise ValueError(f"{path}: regions must be an array")
    by_name = {
        region.get("name"): region
        for region in regions
        if isinstance(region, dict) and isinstance(region.get("name"), str)
    }
    try:
        program = by_name["prog_ram"]
        data = by_name["data_ram"]
        values = (
            int(program["base"]),
            int(program["size_bytes"]),
            int(data["base"]),
            int(data["size_bytes"]),
        )
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(
            f"{path}: prog_ram/data_ram need integer base and size_bytes fields"
        ) from error
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path, help="input RV32 ELF")
    parser.add_argument("--imem", type=Path, required=True, help="instruction $readmemh output")
    parser.add_argument("--dmem", type=Path, required=True, help="data $readmemh output")
    parser.add_argument("--base", type=integer, default=0, help="RAM base address (default: 0)")
    parser.add_argument("--size", type=integer, default=0x4000, help="RAM size in bytes")
    parser.add_argument(
        "--split-map",
        type=Path,
        help="generated simulation map; enables independent program/data images",
    )
    parser.add_argument(
        "--imem-fill",
        type=integer,
        default=0x0010_0073,
        help="word used for uninitialized instruction RAM (default: EBREAK)",
    )
    parser.add_argument(
        "--dmem-uninitialized-fill",
        type=integer,
        default=0,
        help="byte used for split data PT_LOAD memsz/filesz tails (default: 0)",
    )
    args = parser.parse_args()

    try:
        if args.split_map is None:
            elf = convert(
                args.elf,
                args.imem,
                args.dmem,
                args.base,
                args.size,
                args.imem_fill,
            )
            geometry = f"RAM=0x{args.base:08x}+0x{args.size:x}"
        else:
            program_base, program_size, data_base, data_size = (
                split_regions_from_map(args.split_map)
            )
            elf = convert_split(
                args.elf,
                args.imem,
                args.dmem,
                program_base,
                program_size,
                data_base,
                data_size,
                args.imem_fill,
                args.dmem_uninitialized_fill,
            )
            geometry = (
                f"program=0x{program_base:08x}+0x{program_size:x}, "
                f"data=0x{data_base:08x}+0x{data_size:x}"
            )
    except (OSError, ValueError, struct.error) as error:
        parser.error(str(error))

    print(
        f"Converted {args.elf}: entry=0x{elf.entry:08x}, "
        f"segments={len(elf.segments)}, {geometry}"
    )
    print(f"  imem: {args.imem}")
    print(f"  dmem: {args.dmem}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
