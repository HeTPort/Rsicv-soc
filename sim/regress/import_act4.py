#!/usr/bin/env python3
"""Convert ACT4 self-checking ELFs and create a regression manifest."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from elf_to_mem import convert, integer


def safe_name(relative_elf: Path) -> str:
    stem = relative_elf.as_posix()
    if stem.endswith(".elf"):
        stem = stem[:-4]
    return re.sub(r"[^A-Za-z0-9_.-]+", "__", stem).strip("_.-")


def extension_tag(relative_elf: Path) -> str | None:
    """Return the repository tag for an ACT4 I/M extension directory."""
    extension = relative_elf.parent.name.upper()
    return {"I": "rv32i", "M": "rv32m"}.get(extension)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    default_repo = script_dir.parent.parent

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf_dir", type=Path, help="ACT4 directory containing final self-checking ELFs")
    parser.add_argument("--repo-root", type=Path, default=default_repo)
    parser.add_argument("--output-dir", type=Path, default=default_repo / "build" / "act4" / "images")
    parser.add_argument("--manifest", type=Path, default=default_repo / "build" / "act4" / "tests.json")
    parser.add_argument("--base", type=integer, default=0)
    parser.add_argument("--size", type=integer, default=0x40000)
    parser.add_argument("--tohost", type=integer, default=0x0003_FFFC)
    parser.add_argument("--timeout-cycles", type=integer, default=200_000)
    parser.add_argument("--tag", action="append", default=[], help="additional manifest tag")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    elf_dir = args.elf_dir.resolve()
    output_dir = args.output_dir.resolve()
    manifest_path = args.manifest.resolve()
    if not elf_dir.is_dir():
        parser.error(f"ELF directory does not exist: {elf_dir}")
    try:
        output_dir.relative_to(repo_root)
        manifest_path.relative_to(repo_root)
    except ValueError:
        parser.error("output directory and manifest must be inside the repository")

    elf_paths = sorted(
        path for path in elf_dir.rglob("*.elf") if not path.name.endswith(".sig.elf")
    )
    if not elf_paths:
        parser.error(f"no final .elf files found below {elf_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)
    tests = []
    names: set[str] = set()
    common_tags = list(dict.fromkeys(["act4", *args.tag]))
    ram_depth_words = args.size // 4
    if args.size <= 0 or args.size % 4 != 0:
        parser.error("--size must be a positive multiple of four bytes")
    for elf_path in elf_paths:
        relative_elf = elf_path.relative_to(elf_dir)
        name = safe_name(relative_elf)
        if not name or name in names:
            parser.error(f"ELF paths produce a duplicate/empty test name: {relative_elf}")
        names.add(name)

        imem_path = output_dir / f"{name}.imem.hex"
        dmem_path = output_dir / f"{name}.dmem.hex"
        convert(elf_path, imem_path, dmem_path, args.base, args.size)
        test_tags = list(common_tags)
        inferred_tag = extension_tag(relative_elf)
        if inferred_tag is not None and inferred_tag not in test_tags:
            test_tags.append(inferred_tag)
        tests.append(
            {
                "name": name,
                "image": imem_path.relative_to(repo_root).as_posix(),
                "data_image": dmem_path.relative_to(repo_root).as_posix(),
                "timeout_cycles": args.timeout_cycles,
                "tohost_addr": args.tohost,
                "prog_ram_depth": ram_depth_words,
                "data_ram_depth": ram_depth_words,
                "tags": test_tags,
            }
        )

    manifest = {
        "schema_version": 1,
        "defaults": {
            "timeout_cycles": args.timeout_cycles,
            "tohost_addr": args.tohost,
            "prog_ram_depth": ram_depth_words,
            "data_ram_depth": ram_depth_words,
        },
        "tests": tests,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(tests)} ACT4 ELF(s)")
    print(f"  images:   {output_dir}")
    print(f"  manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
