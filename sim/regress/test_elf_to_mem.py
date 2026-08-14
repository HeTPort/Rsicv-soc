#!/usr/bin/env python3
"""Unit tests for the dependency-free ELF-to-memory converter."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from elf_to_mem import (
    build_memories,
    build_split_memories,
    convert,
    convert_split,
    read_elf,
)


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

    def test_split_regions_keep_program_and_data_separate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(
                elf_path,
                [
                    (0x0000, b"\x13\x00\x00\x00", 4, 5),
                    (0x8000, b"\x78\x56\x34\x12", 8, 6),
                ],
            )

            imem, dmem = build_split_memories(
                read_elf(elf_path),
                program_base=0x0000,
                program_size=0x20,
                data_base=0x8000,
                data_size=0x20,
                instruction_fill=0x0010_0073,
            )

            self.assertEqual(int.from_bytes(imem[0:4], "little"), 0x0000_0013)
            self.assertEqual(int.from_bytes(imem[4:8], "little"), 0x0010_0073)
            self.assertEqual(int.from_bytes(dmem[0:4], "little"), 0x1234_5678)
            self.assertEqual(dmem[4:8], bytes(4))

    def test_split_conversion_trims_each_local_image_independently(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            elf_path = root / "fixture.elf"
            imem_path = root / "fixture.imem.hex"
            dmem_path = root / "fixture.dmem.hex"
            make_elf32(
                elf_path,
                [
                    (0x0000, b"\x93\x00\x10\x00", 4, 5),
                    (0x8008, b"\xef\xbe\xad\xde", 4, 6),
                ],
            )

            convert_split(
                elf_path,
                imem_path,
                dmem_path,
                program_base=0x0000,
                program_size=0x20,
                data_base=0x8000,
                data_size=0x20,
            )

            self.assertEqual(imem_path.read_text().splitlines(), ["00100093"])
            self.assertEqual(
                dmem_path.read_text().splitlines(),
                ["00000000", "00000000", "deadbeef"],
            )

    def test_split_regions_accept_exact_word_boundaries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(
                elf_path,
                [
                    (0x0000, bytes(4), 4, 5),
                    (0x000C, b"\x13\x00\x00\x00", 4, 5),
                    (0x8000, b"\x01\x02\x03\x04", 4, 6),
                    (0x800C, b"\x05\x06\x07\x08", 4, 6),
                ],
            )
            imem, dmem = build_split_memories(
                read_elf(elf_path), 0, 0x10, 0x8000, 0x10, 0x0010_0073
            )
            self.assertEqual(imem[0xC:0x10], b"\x13\x00\x00\x00")
            self.assertEqual(dmem[0xC:0x10], b"\x05\x06\x07\x08")

    def test_split_regions_reject_a_boundary_crossing_segment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(elf_path, [(0x000C, bytes(4), 8, 5)])
            with self.assertRaisesRegex(ValueError, "not wholly inside"):
                build_split_memories(
                    read_elf(elf_path), 0, 0x10, 0x8000, 0x10, 0x0010_0073
                )

    def test_split_regions_reject_mmio_or_unmapped_segment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(
                elf_path,
                [(0x0000, bytes(4), 4, 5), (0x1000, bytes(4), 4, 6)],
            )
            with self.assertRaisesRegex(ValueError, "not wholly inside"):
                build_split_memories(
                    read_elf(elf_path), 0, 0x10, 0x8000, 0x10, 0x0010_0073
                )

    def test_split_regions_reject_conflicting_overlap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(
                elf_path,
                [
                    (0x0000, b"\x13\x00\x00\x00", 4, 5),
                    (0x0000, b"\x93\x00\x10\x00", 4, 5),
                ],
            )
            with self.assertRaisesRegex(ValueError, "conflicting PT_LOAD bytes"):
                build_split_memories(
                    read_elf(elf_path), 0, 0x10, 0x8000, 0x10, 0x0010_0073
                )

    def test_split_regions_require_entry_at_reset_base(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(elf_path, [(0x0000, bytes(8), 8, 5)], entry=4)
            with self.assertRaisesRegex(ValueError, "does not equal reset entry"):
                build_split_memories(
                    read_elf(elf_path), 0, 0x10, 0x8000, 0x10, 0x0010_0073
                )

    def test_split_regions_can_poison_data_uninitialized_tail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            elf_path = Path(temporary) / "fixture.elf"
            make_elf32(
                elf_path,
                [
                    (0x0000, bytes(4), 4, 5),
                    (0x8000, b"\x78\x56\x34\x12", 8, 6),
                ],
            )
            _, dmem = build_split_memories(
                read_elf(elf_path),
                0,
                0x10,
                0x8000,
                0x10,
                0x0010_0073,
                data_uninitialized_fill=0xA5,
            )
            self.assertEqual(dmem[0:4], b"\x78\x56\x34\x12")
            self.assertEqual(dmem[4:8], b"\xA5\xA5\xA5\xA5")


if __name__ == "__main__":
    unittest.main()
