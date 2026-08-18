#!/usr/bin/env python3
"""Integration test for ACT4 ELF import and manifest generation."""

from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def write_fixture_elf(path: Path) -> None:
    ident = bytearray(16)
    ident[:4] = b"\x7fELF"
    ident[4:7] = bytes((1, 1, 1))
    code = bytes.fromhex(
        "93001000 b7420000 9382c2ff 23a01200 6f000000".replace(" ", "")
    )
    data = bytes.fromhex("00110040")
    segments = [(0, code, 5), (0x200, data, 6)]
    header_size = 52
    ph_size = 32
    payload_offset = header_size + ph_size * len(segments)
    header = struct.pack(
        "<16sHHIIIIIHHHHHH",
        bytes(ident), 2, 243, 1, 0, header_size, 0, 0,
        header_size, ph_size, len(segments), 0, 0, 0,
    )
    phdrs = bytearray()
    payload = bytearray()
    for address, contents, flags in segments:
        offset = payload_offset + len(payload)
        phdrs.extend(
            struct.pack("<IIIIIIII", 1, offset, address, address, len(contents), len(contents), flags, 4)
        )
        payload.extend(contents)
    path.write_bytes(header + phdrs + payload)


class ImportAct4Tests(unittest.TestCase):
    def test_import_creates_images_and_runner_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            elf_dir = repo / "elfs"
            i_dir = elf_dir / "rv32i" / "I"
            m_dir = elf_dir / "rv32i" / "M"
            i_dir.mkdir(parents=True)
            m_dir.mkdir(parents=True)
            write_fixture_elf(i_dir / "I-ADDI-01.elf")
            write_fixture_elf(m_dir / "M-MUL-01.elf")
            script = Path(__file__).resolve().parent / "import_act4.py"
            result = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    str(elf_dir),
                    "--repo-root", str(repo),
                    "--output-dir", str(repo / "build/images"),
                    "--manifest", str(repo / "build/tests.json"),
                    "--tag", "release-baseline",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((repo / "build/tests.json").read_text())
            tests = {test["name"]: test for test in manifest["tests"]}
            self.assertEqual(set(tests), {"rv32i__I__I-ADDI-01", "rv32i__M__M-MUL-01"})
            for test in tests.values():
                self.assertEqual(test["tohost_addr"], 0x0003_FFFC)
                self.assertEqual(test["prog_ram_depth"], 0x40000 // 4)
                self.assertEqual(test["data_ram_depth"], 0x40000 // 4)
                self.assertIn("release-baseline", test["tags"])
                self.assertTrue((repo / test["image"]).is_file())
                self.assertTrue((repo / test["data_image"]).is_file())

            self.assertIn("rv32i", tests["rv32i__I__I-ADDI-01"]["tags"])
            self.assertNotIn("rv32m", tests["rv32i__I__I-ADDI-01"]["tags"])
            self.assertIn("rv32m", tests["rv32i__M__M-MUL-01"]["tags"])
            self.assertNotIn("rv32i", tests["rv32i__M__M-MUL-01"]["tags"])


if __name__ == "__main__":
    unittest.main()
