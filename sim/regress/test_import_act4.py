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
            elf_dir.mkdir()
            write_fixture_elf(elf_dir / "I-ADDI-01.elf")
            script = Path(__file__).resolve().parent / "import_act4.py"
            result = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    str(elf_dir),
                    "--repo-root", str(repo),
                    "--output-dir", str(repo / "build/images"),
                    "--manifest", str(repo / "build/tests.json"),
                    "--tag", "rv32i",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((repo / "build/tests.json").read_text())
            self.assertEqual(manifest["tests"][0]["name"], "I-ADDI-01")
            self.assertEqual(manifest["tests"][0]["tohost_addr"], 0x0000_3FFC)
            self.assertIn("rv32i", manifest["tests"][0]["tags"])
            self.assertTrue((repo / manifest["tests"][0]["image"]).is_file())
            self.assertTrue((repo / manifest["tests"][0]["data_image"]).is_file())


if __name__ == "__main__":
    unittest.main()
