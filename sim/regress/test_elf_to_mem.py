#!/usr/bin/env python3
"""Unit tests for the dependency-free ELF-to-memory converter."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from elf_to_mem import build_memories, convert, read_elf


def make_elf32(path: Path, segments: list[tuple[int, bytes, int, int]], entry: int = 0) -> None:
    """Create the small ELF32 fixture needed by these converter tests."""
    ident = bytearray(16)
    ident[:4] = b"\x7fELF"
    ident[4] = 1
    ident[5] = 1
    ident[6] = 1
    header_size = 52
    ph_size = 32
    data_offset = header_size + ph_size * len(segments)
    header = struct.pack(
        "<16sHHIIIIIHHHHHH",
        bytes(ident), 2, 243, 1, entry, header_size, 0, 0,
        header_size, ph_size, len(segments), 0, 0, 0,
    )

    program_headers = bytearray()
    payload = bytearray()
    for address, data, memory_size, flags in segments:
        offset = data_offset + len(payload)
        program_headers.extend(
            struct.pack("<IIIIIIII", 1, offset, address, address, len(data), memory_size, flags, 4)
        )
        payload.extend(data)
    path.write_bytes(header + program_headers + payload)


class ElfToMemTests(unittest.TestCase):
    def test_loads_code_data_and_bss_into_both_harvard_memories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            elf_path = root / "fixture.elf"
            make_elf32(
                elf_path,
                [
                    (0x000, b"\x13\x00\x00\x00", 4, 5),
                    (0x200, b"\x00\x11\x00\x40", 8, 6),
                ],
            )
            elf = read_elf(elf_path)
            imem, dmem = build_memories(elf, 0, 0x400, 0x0010_0073)

            self.assertEqual(int.from_bytes(imem[0:4], "little"), 0x0000_0013)
            self.assertEqual(int.from_bytes(dmem[0:4], "little"), 0x0000_0013)
            self.assertEqual(int.from_bytes(imem[0x200:0x204], "little"), 0x4000_1100)
            self.assertEqual(dmem[0x204:0x208], bytes(4))
            self.assertEqual(int.from_bytes(imem[4:8], "little"), 0x0010_0073)
            self.assertEqual(dmem[4:8], bytes(4))

    def test_writes_readmemh_words(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            elf_path = root / "fixture.elf"
            imem_path = root / "fixture.imem.hex"
            dmem_path = root / "fixture.dmem.hex"
            make_elf32(elf_path, [(0, b"\x93\x00\x10\x00", 4, 5)])
            convert(elf_path, imem_path, dmem_path, size=16)
            self.assertEqual(imem_path.read_text().splitlines()[0], "00100093")
            self.assertEqual(dmem_path.read_text().splitlines()[0], "00100093")

    def test_rejects_a_segment_outside_ram(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(elf_path, [(0x400, bytes(4), 4, 6)])
            with self.assertRaisesRegex(ValueError, "outside configured RAM"):
                build_memories(read_elf(elf_path), 0, 0x400, 0x0010_0073)


if __name__ == "__main__":
    unittest.main()
