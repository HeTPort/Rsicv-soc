#!/usr/bin/env python3
"""Unit tests for the dependency-free SoC map generator."""

from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_soc_map import (  # noqa: E402
    ConfigError,
    find_outdated,
    load_config,
    render_outputs,
    validate_config,
    write_outputs,
)


class SocMapGeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source_path = REPO_ROOT / "config" / "soc_map.json"
        cls.raw = json.loads(cls.source_path.read_text(encoding="utf-8"))

    def test_normalizes_accepted_64k_map(self) -> None:
        config = load_config(self.source_path)
        regions = {region["name"]: region for region in config["regions"]}
        self.assertEqual(config["name"], "freertos_split_64k_v1")
        self.assertEqual(config["status"], "accepted")
        self.assertEqual(regions["prog_ram"]["depth_words"], 16_384)
        self.assertEqual(regions["data_ram"]["depth_words"], 16_384)
        self.assertEqual(config["simulation"]["tohost"]["address"], 0x8000_FFFC)
        self.assertEqual(
            {register["name"]: register["address"] for register in config["registers"]},
            {
                "mtimecmp": 0x0200_4000,
                "mtime": 0x0200_BFF8,
                "uart_txdata": 0x1000_0000,
                "uart_status": 0x1000_0004,
                "uart_rxdata": 0x1000_0008,
                "uart_rxerror": 0x1000_000C,
                "gpio_out": 0x1000_1000,
            },
        )

    def test_rejects_overlapping_regions(self) -> None:
        raw = copy.deepcopy(self.raw)
        raw["regions"][3]["base"] = raw["regions"][2]["base"]
        with self.assertRaisesRegex(ConfigError, "overlap"):
            validate_config(raw)

    def test_rejects_noncanonical_tohost_placement(self) -> None:
        raw = copy.deepcopy(self.raw)
        raw["simulation"]["tohost"]["placement"] = "fixed_offset"
        with self.assertRaisesRegex(ConfigError, "last_word"):
            validate_config(raw)

    def test_generation_is_deterministic_and_checkable(self) -> None:
        config = load_config(self.source_path)
        outputs = render_outputs(config)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertEqual(set(find_outdated(root, outputs)), set(outputs))
            write_outputs(root, outputs)
            self.assertEqual(find_outdated(root, outputs), [])
            first_path = root / next(iter(outputs))
            first_path.write_text("stale\n", encoding="utf-8")
            self.assertEqual(find_outdated(root, outputs), [next(iter(outputs))])

    def test_checked_in_outputs_match_authoritative_source(self) -> None:
        config = load_config(self.source_path)
        self.assertEqual(find_outdated(REPO_ROOT, render_outputs(config)), [])

    def test_synthesis_script_consumes_generated_ram_depths(self) -> None:
        script = (
            REPO_ROOT / "sim" / "synth" / "check_riscv_soc_configured_ram.tcl"
        ).read_text(encoding="utf-8")
        self.assertIn("source $map_tcl", script)
        self.assertIn("PROG_RAM_DEPTH=$SOC_PROG_RAM_DEPTH_WORDS", script)
        self.assertIn("DATA_RAM_DEPTH=$SOC_DATA_RAM_DEPTH_WORDS", script)

    def test_generates_16k_and_64k_utilization_profiles(self) -> None:
        config = load_config(self.source_path)
        self.assertEqual(
            config["utilization_experiments"],
            [
                {"name": "ram_16k", "bank_bytes": 16_384, "depth_words": 4_096},
                {"name": "ram_64k", "bank_bytes": 65_536, "depth_words": 16_384},
            ],
        )
        profile_tcl = render_outputs(config)[
            Path("sim/generated/soc_ram_utilization_profiles.tcl")
        ]
        self.assertIn("set SOC_RAM_UTILIZATION_PROFILE_NAMES [list ram_16k ram_64k]", profile_tcl)

    def test_comparison_script_consumes_generated_profiles(self) -> None:
        script = (
            REPO_ROOT / "sim" / "synth" / "compare_riscv_soc_ram_utilization.tcl"
        ).read_text(encoding="utf-8")
        self.assertIn("soc_ram_utilization_profiles.tcl", script)
        self.assertIn("SOC_RAM_UTILIZATION_DEPTH_WORDS($profile_name)", script)

    def test_timing_script_consumes_generated_profiles_and_profile_dcp(self) -> None:
        script = (
            REPO_ROOT / "sim" / "synth" / "report_riscv_soc_ram_timing.tcl"
        ).read_text(encoding="utf-8")
        self.assertIn("soc_ram_utilization_profiles.tcl", script)
        self.assertIn("SOC_RAM_UTILIZATION_DEPTH_WORDS($profile_name)", script)
        self.assertIn("build vivado_$profile_name", script)
        self.assertIn("riscv_soc_synth.dcp", script)
        self.assertIn("create_clock -name core_clk", script)


if __name__ == "__main__":
    unittest.main()
