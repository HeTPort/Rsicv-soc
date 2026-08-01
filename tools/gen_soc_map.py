#!/usr/bin/env python3
"""Validate the SoC map and generate synchronized consumer artifacts.

Only the Python standard library is used so generation works in the Windows,
WSL, and CI environments already used by this repository.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from pathlib import Path
from typing import Any


NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
ALLOWED_STATUS = {"proposed", "accepted", "implemented"}
ALLOWED_KINDS = {"ram", "mmio"}


class ConfigError(ValueError):
    """The authoritative map is malformed or internally inconsistent."""


def parse_integer(value: Any, field: str) -> int:
    if isinstance(value, bool):
        raise ConfigError(f"{field} must be an integer, not a boolean")
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError as error:
            raise ConfigError(f"{field} is not a valid integer: {value!r}") from error
    raise ConfigError(f"{field} must be an integer or prefixed integer string")


def is_power_of_two(value: int) -> bool:
    return value > 0 and (value & (value - 1)) == 0


def require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError(f"{field} must be an object")
    return value


def require_list(value: Any, field: str) -> list[Any]:
    if not isinstance(value, list):
        raise ConfigError(f"{field} must be an array")
    return value


def validate_config(raw: dict[str, Any]) -> dict[str, Any]:
    """Return a normalized copy whose numeric fields are Python integers."""

    config = copy.deepcopy(raw)
    if config.get("schema_version") != 1:
        raise ConfigError("schema_version must be 1")

    name = config.get("name")
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        raise ConfigError("name must match [a-z][a-z0-9_]*")

    status = config.get("status")
    if status not in ALLOWED_STATUS:
        raise ConfigError(f"status must be one of {sorted(ALLOWED_STATUS)}")

    address_width = parse_integer(config.get("address_width"), "address_width")
    data_width = parse_integer(config.get("data_width"), "data_width")
    if address_width <= 0 or address_width > 64:
        raise ConfigError("address_width must be in the range 1..64")
    if data_width <= 0 or data_width % 8 != 0:
        raise ConfigError("data_width must be a positive multiple of 8")
    word_bytes = data_width // 8
    if not is_power_of_two(word_bytes):
        raise ConfigError("bytes per data word must be a power of two")
    config["address_width"] = address_width
    config["data_width"] = data_width
    config["word_bytes"] = word_bytes

    regions = require_list(config.get("regions"), "regions")
    if not regions:
        raise ConfigError("regions must not be empty")
    names: set[str] = set()
    normalized_regions: list[dict[str, Any]] = []
    address_limit = 1 << address_width

    for index, raw_region in enumerate(regions):
        region = require_mapping(raw_region, f"regions[{index}]")
        region_name = region.get("name")
        if not isinstance(region_name, str) or not NAME_RE.fullmatch(region_name):
            raise ConfigError(f"regions[{index}].name is invalid")
        if region_name in names:
            raise ConfigError(f"duplicate region name: {region_name}")
        names.add(region_name)

        kind = region.get("kind")
        if kind not in ALLOWED_KINDS:
            raise ConfigError(f"region {region_name} has unsupported kind {kind!r}")
        permissions = region.get("permissions")
        if not isinstance(permissions, str) or not permissions or any(
            letter not in "rwx" for letter in permissions
        ):
            raise ConfigError(f"region {region_name} has invalid permissions")

        base = parse_integer(region.get("base"), f"region {region_name}.base")
        size = parse_integer(
            region.get("size_bytes"), f"region {region_name}.size_bytes"
        )
        if base < 0 or size <= 0 or base + size > address_limit:
            raise ConfigError(f"region {region_name} lies outside the address space")
        if not is_power_of_two(size):
            raise ConfigError(f"region {region_name} size must be a power of two")
        if base % size != 0:
            raise ConfigError(f"region {region_name} base must be size-aligned")
        if kind == "ram" and size % word_bytes != 0:
            raise ConfigError(f"RAM region {region_name} must contain complete words")

        normalized = dict(region)
        normalized["base"] = base
        normalized["size_bytes"] = size
        normalized["end"] = base + size - 1
        if kind == "ram":
            normalized["depth_words"] = size // word_bytes
        normalized_regions.append(normalized)

    sorted_regions = sorted(normalized_regions, key=lambda item: item["base"])
    for left, right in zip(sorted_regions, sorted_regions[1:]):
        if left["end"] >= right["base"]:
            raise ConfigError(
                f"regions {left['name']} and {right['name']} overlap"
            )
    config["regions"] = normalized_regions
    region_by_name = {region["name"]: region for region in normalized_regions}
    for required_region in ("prog_ram", "data_ram"):
        if required_region not in region_by_name:
            raise ConfigError(f"required region is missing: {required_region}")
        if region_by_name[required_region]["kind"] != "ram":
            raise ConfigError(f"required region {required_region} must be RAM")

    normalized_registers: list[dict[str, Any]] = []
    occupied_registers: dict[str, list[tuple[int, int, str]]] = {}
    register_names: set[str] = set()
    for index, raw_register in enumerate(
        require_list(config.get("registers", []), "registers")
    ):
        register = require_mapping(raw_register, f"registers[{index}]")
        register_name = register.get("name")
        if not isinstance(register_name, str) or not NAME_RE.fullmatch(register_name):
            raise ConfigError(f"registers[{index}].name is invalid")
        if register_name in register_names:
            raise ConfigError(f"duplicate register name: {register_name}")
        register_names.add(register_name)
        region_name = register.get("region")
        if region_name not in region_by_name:
            raise ConfigError(f"register {register_name} names unknown region")
        offset = parse_integer(register.get("offset"), f"register {register_name}.offset")
        width_bits = parse_integer(
            register.get("width_bits"), f"register {register_name}.width_bits"
        )
        if offset < 0 or width_bits <= 0 or width_bits % 8 != 0:
            raise ConfigError(f"register {register_name} has invalid offset or width")
        width_bytes = width_bits // 8
        region = region_by_name[region_name]
        if offset + width_bytes > region["size_bytes"]:
            raise ConfigError(f"register {register_name} does not fit in {region_name}")
        if offset % min(width_bytes, word_bytes) != 0:
            raise ConfigError(f"register {register_name} is not naturally aligned")
        for start, end, other_name in occupied_registers.setdefault(region_name, []):
            if offset < end and offset + width_bytes > start:
                raise ConfigError(
                    f"registers {other_name} and {register_name} overlap"
                )
        occupied_registers[region_name].append(
            (offset, offset + width_bytes, register_name)
        )
        normalized = dict(register)
        normalized["offset"] = offset
        normalized["width_bits"] = width_bits
        normalized["address"] = region["base"] + offset
        normalized_registers.append(normalized)
    config["registers"] = normalized_registers

    simulation = require_mapping(config.get("simulation"), "simulation")
    tohost = require_mapping(simulation.get("tohost"), "simulation.tohost")
    tohost_region_name = tohost.get("region")
    if tohost_region_name not in region_by_name:
        raise ConfigError("simulation.tohost names an unknown region")
    tohost_region = region_by_name[tohost_region_name]
    if tohost_region["kind"] != "ram":
        raise ConfigError("simulation.tohost must be located in RAM")
    if tohost.get("placement") != "last_word":
        raise ConfigError("simulation.tohost placement must be last_word")
    tohost_size = word_bytes
    tohost_offset = tohost_region["size_bytes"] - word_bytes
    normalized_tohost = dict(tohost)
    normalized_tohost["offset"] = tohost_offset
    normalized_tohost["size_bytes"] = tohost_size
    normalized_tohost["address"] = tohost_region["base"] + tohost_offset
    config["simulation"] = {"tohost": normalized_tohost}

    default_target = require_mapping(config.get("default_target"), "default_target")
    default_target["read_data"] = parse_integer(
        default_target.get("read_data"), "default_target.read_data"
    )
    for field in ("response_error", "write_side_effect"):
        if not isinstance(default_target.get(field), bool):
            raise ConfigError(f"default_target.{field} must be boolean")
    if not default_target["response_error"]:
        raise ConfigError("default target must report an error")
    if default_target["write_side_effect"]:
        raise ConfigError("default target writes must be side-effect-free")
    if default_target["read_data"] < 0 or default_target["read_data"] >= (1 << data_width):
        raise ConfigError("default_target.read_data does not fit data_width")
    config["default_target"] = default_target

    experiments = require_mapping(
        config.get("utilization_experiments"), "utilization_experiments"
    )
    raw_sizes = require_list(
        experiments.get("ram_bank_sizes_bytes"),
        "utilization_experiments.ram_bank_sizes_bytes",
    )
    if len(raw_sizes) < 2:
        raise ConfigError("at least two RAM utilization sizes are required")
    normalized_profiles: list[dict[str, int | str]] = []
    seen_sizes: set[int] = set()
    for index, raw_size in enumerate(raw_sizes):
        size = parse_integer(
            raw_size,
            f"utilization_experiments.ram_bank_sizes_bytes[{index}]",
        )
        if size in seen_sizes:
            raise ConfigError(f"duplicate RAM utilization size: {size}")
        if not is_power_of_two(size) or size % word_bytes != 0:
            raise ConfigError(
                "RAM utilization sizes must be unique power-of-two whole-word capacities"
            )
        seen_sizes.add(size)
        size_kib = size // 1024
        profile_name = f"ram_{size_kib}k" if size % 1024 == 0 else f"ram_{size}b"
        normalized_profiles.append(
            {
                "name": profile_name,
                "bank_bytes": size,
                "depth_words": size // word_bytes,
            }
        )
    config["utilization_experiments"] = sorted(
        normalized_profiles, key=lambda profile: int(profile["bank_bytes"])
    )
    return config


def load_config(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigError(f"cannot read {path}: {error}") from error
    return validate_config(require_mapping(raw, "root"))


def hex_literal(value: int, width_bits: int) -> str:
    digits = (width_bits + 3) // 4
    return f"{width_bits}'h{value:0{digits}X}"


def hex_c(value: int, width_bits: int) -> str:
    digits = (width_bits + 3) // 4
    suffix = "ULL" if width_bits > 32 else "u"
    return f"0x{value:0{digits}X}{suffix}"


def generated_banner(config: dict[str, Any], comment: str) -> list[str]:
    return [
        f"{comment} Generated by tools/gen_soc_map.py from config/soc_map.json.",
        f"{comment} Configuration: {config['name']} ({config['status']}).",
        f"{comment} Do not edit this file directly.",
    ]


def render_systemverilog(config: dict[str, Any]) -> str:
    aw = config["address_width"]
    dw = config["data_width"]
    lines = generated_banner(config, "//")
    lines.extend(
        [
            "package soc_mem_map_pkg;",
            f"  localparam int unsigned SOC_ADDRESS_WIDTH = {aw};",
            f"  localparam int unsigned SOC_DATA_WIDTH = {dw};",
            f"  localparam int unsigned SOC_WORD_BYTES = {config['word_bytes']};",
            "",
        ]
    )
    for region in config["regions"]:
        prefix = f"SOC_{region['name'].upper()}"
        lines.extend(
            [
                f"  localparam logic [SOC_ADDRESS_WIDTH-1:0] {prefix}_BASE = {hex_literal(region['base'], aw)};",
                f"  localparam logic [SOC_ADDRESS_WIDTH-1:0] {prefix}_END = {hex_literal(region['end'], aw)};",
                f"  localparam int unsigned {prefix}_BYTES = {region['size_bytes']};",
            ]
        )
        if region["kind"] == "ram":
            lines.append(
                f"  localparam int unsigned {prefix}_DEPTH_WORDS = {region['depth_words']};"
            )
        lines.append("")
    for register in config["registers"]:
        prefix = f"SOC_{register['name'].upper()}"
        lines.extend(
            [
                f"  localparam logic [SOC_ADDRESS_WIDTH-1:0] {prefix}_ADDR = {hex_literal(register['address'], aw)};",
                f"  localparam int unsigned {prefix}_WIDTH_BITS = {register['width_bits']};",
            ]
        )
    if config["registers"]:
        lines.append("")
    tohost = config["simulation"]["tohost"]
    lines.append(
        f"  localparam logic [SOC_ADDRESS_WIDTH-1:0] SOC_TOHOST_ADDR = {hex_literal(tohost['address'], aw)};"
    )
    default = config["default_target"]
    lines.extend(
        [
            f"  localparam logic [SOC_DATA_WIDTH-1:0] SOC_DEFAULT_RDATA = {hex_literal(default['read_data'], dw)};",
            f"  localparam bit SOC_DEFAULT_RESPONSE_ERROR = 1'b{int(default['response_error'])};",
            f"  localparam bit SOC_DEFAULT_WRITE_SIDE_EFFECT = 1'b{int(default['write_side_effect'])};",
            "endpackage",
            "",
        ]
    )
    return "\n".join(lines)


def render_c_header(config: dict[str, Any]) -> str:
    aw = config["address_width"]
    lines = generated_banner(config, "/*")
    lines[0] += " */"
    lines[1] += " */"
    lines[2] += " */"
    lines.extend(
        [
            "#ifndef SOC_MEMORY_MAP_H",
            "#define SOC_MEMORY_MAP_H",
            "",
            f"#define SOC_ADDRESS_WIDTH {config['address_width']}u",
            f"#define SOC_DATA_WIDTH {config['data_width']}u",
            f"#define SOC_WORD_BYTES {config['word_bytes']}u",
            "",
        ]
    )
    for region in config["regions"]:
        prefix = f"SOC_{region['name'].upper()}"
        lines.extend(
            [
                f"#define {prefix}_BASE {hex_c(region['base'], aw)}",
                f"#define {prefix}_END {hex_c(region['end'], aw)}",
                f"#define {prefix}_BYTES {region['size_bytes']}u",
            ]
        )
        if region["kind"] == "ram":
            lines.append(f"#define {prefix}_DEPTH_WORDS {region['depth_words']}u")
        lines.append("")
    for register in config["registers"]:
        prefix = f"SOC_{register['name'].upper()}"
        lines.extend(
            [
                f"#define {prefix}_ADDR {hex_c(register['address'], aw)}",
                f"#define {prefix}_WIDTH_BITS {register['width_bits']}u",
            ]
        )
    if config["registers"]:
        lines.append("")
    lines.extend(
        [
            f"#define SOC_TOHOST_ADDR {hex_c(config['simulation']['tohost']['address'], aw)}",
            "",
            "#endif",
            "",
        ]
    )
    return "\n".join(lines)


def render_linker(config: dict[str, Any]) -> str:
    regions = {region["name"]: region for region in config["regions"]}
    prog = regions["prog_ram"]
    data = regions["data_ram"]
    tohost = config["simulation"]["tohost"]
    lines = generated_banner(config, "/*")
    lines[0] += " */"
    lines[1] += " */"
    lines[2] += " */"
    lines.extend(
        [
            "MEMORY",
            "{",
            f"  prog_ram (rx) : ORIGIN = 0x{prog['base']:08x}, LENGTH = 0x{prog['size_bytes']:08x}",
            f"  data_ram (rw) : ORIGIN = 0x{data['base']:08x}, LENGTH = 0x{data['size_bytes']:08x}",
            "}",
            "",
            f"SOC_TOHOST_ADDR = 0x{tohost['address']:08x};",
            "PROVIDE(__soc_tohost = SOC_TOHOST_ADDR);",
            "ASSERT(SOC_TOHOST_ADDR >= ORIGIN(data_ram), \"tohost below data RAM\")",
            "ASSERT(SOC_TOHOST_ADDR + 4 <= ORIGIN(data_ram) + LENGTH(data_ram), \"tohost outside data RAM\")",
            "",
        ]
    )
    return "\n".join(lines)


def render_sim_json(config: dict[str, Any]) -> str:
    normalized = {
        "schema_version": config["schema_version"],
        "name": config["name"],
        "status": config["status"],
        "address_width": config["address_width"],
        "data_width": config["data_width"],
        "word_bytes": config["word_bytes"],
        "regions": [
            {
                key: region[key]
                for key in (
                    "name",
                    "kind",
                    "base",
                    "end",
                    "size_bytes",
                    "permissions",
                    "depth_words",
                )
                if key in region
            }
            for region in config["regions"]
        ],
        "registers": config["registers"],
        "tohost_addr": config["simulation"]["tohost"]["address"],
        "default_target": config["default_target"],
    }
    return json.dumps(normalized, indent=2, sort_keys=True) + "\n"


def render_act4_yaml(config: dict[str, Any]) -> str:
    lines = generated_banner(config, "#")
    lines.extend(
        [
            "# This is a map fragment for future ACT4 integration, not a complete UDB file.",
            f"name: {config['name']}",
            f"status: {config['status']}",
            f"address_width: {config['address_width']}",
            f"data_width: {config['data_width']}",
            "regions:",
        ]
    )
    for region in config["regions"]:
        lines.extend(
            [
                f"  - name: {region['name']}",
                f"    kind: {region['kind']}",
                f"    base: 0x{region['base']:08x}",
                f"    size_bytes: 0x{region['size_bytes']:08x}",
                f"    permissions: {region['permissions']}",
            ]
        )
    lines.extend(
        [
            f"tohost_addr: 0x{config['simulation']['tohost']['address']:08x}",
            "",
        ]
    )
    return "\n".join(lines)


def render_tcl(config: dict[str, Any]) -> str:
    lines = generated_banner(config, "#")
    lines.extend(
        [
            f"set SOC_MAP_NAME {config['name']}",
            f"set SOC_MAP_STATUS {config['status']}",
            f"set SOC_ADDRESS_WIDTH {config['address_width']}",
            f"set SOC_DATA_WIDTH {config['data_width']}",
        ]
    )
    for region in config["regions"]:
        prefix = f"SOC_{region['name'].upper()}"
        lines.extend(
            [
                f"set {prefix}_BASE 0x{region['base']:08x}",
                f"set {prefix}_BYTES {region['size_bytes']}",
            ]
        )
        if region["kind"] == "ram":
            lines.append(f"set {prefix}_DEPTH_WORDS {region['depth_words']}")
    lines.extend(
        [
            f"set SOC_TOHOST_ADDR 0x{config['simulation']['tohost']['address']:08x}",
            "",
        ]
    )
    return "\n".join(lines)


def render_utilization_profiles_tcl(config: dict[str, Any]) -> str:
    lines = generated_banner(config, "#")
    profiles = config["utilization_experiments"]
    names = " ".join(str(profile["name"]) for profile in profiles)
    lines.extend(
        [
            f"set SOC_RAM_UTILIZATION_SOURCE_MAP {config['name']}",
            f"set SOC_RAM_UTILIZATION_PROFILE_NAMES [list {names}]",
            "array set SOC_RAM_UTILIZATION_BANK_BYTES {",
        ]
    )
    for profile in profiles:
        lines.append(f"  {profile['name']} {profile['bank_bytes']}")
    lines.extend(["}", "array set SOC_RAM_UTILIZATION_DEPTH_WORDS {"])
    for profile in profiles:
        lines.append(f"  {profile['name']} {profile['depth_words']}")
    lines.extend(["}", ""])
    return "\n".join(lines)


def render_outputs(config: dict[str, Any]) -> dict[Path, str]:
    return {
        Path("src/generated/soc_mem_map_pkg.sv"): render_systemverilog(config),
        Path("firmware/include/soc_memory_map.h"): render_c_header(config),
        Path("firmware/linker/soc_memory.ldh"): render_linker(config),
        Path("sim/generated/soc_map.json"): render_sim_json(config),
        Path("sim/generated/soc_map.tcl"): render_tcl(config),
        Path("sim/generated/soc_ram_utilization_profiles.tcl"): render_utilization_profiles_tcl(config),
        Path("verif/act4/generated_memory_map.yaml"): render_act4_yaml(config),
    }


def find_outdated(root: Path, outputs: dict[Path, str]) -> list[Path]:
    outdated: list[Path] = []
    for relative_path, expected in outputs.items():
        path = root / relative_path
        try:
            actual = path.read_text(encoding="utf-8")
        except OSError:
            outdated.append(relative_path)
            continue
        if actual != expected:
            outdated.append(relative_path)
    return outdated


def write_outputs(root: Path, outputs: dict[Path, str]) -> None:
    for relative_path, content in outputs.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    repository = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path, default=repository, help="repository output root"
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=repository / "config" / "soc_map.json",
        help="authoritative JSON source",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when generated files are missing or stale",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        config = load_config(args.config.resolve())
        outputs = render_outputs(config)
        if args.check:
            outdated = find_outdated(args.root.resolve(), outputs)
            if outdated:
                for path in outdated:
                    print(f"OUTDATED: {path}", file=sys.stderr)
                return 1
            print(f"SoC map check passed: {config['name']} ({config['status']})")
            return 0
        write_outputs(args.root.resolve(), outputs)
        for path in outputs:
            print(f"GENERATED: {path}")
        return 0
    except ConfigError as error:
        print(f"SoC map configuration error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
